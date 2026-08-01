# USB 独占完整接入指南

本文面向 sylvakru 原作者，说明如何从最新 `origin/main` 手工接入当前完整 USB 独占链路。它不依赖本分支的历史提交，也不要求沿用本分支的设置页、状态胶囊、音量浮层或其它 UI。

接口字段和 JNI 数组布局见 [USB 独占接口参考](usb-exclusive-native-api.md)，新 DAC 取证与 quirk 见 [USB DAC 适配指南](dac-adaptation-guide.md)。

## 1. 适用范围与非目标

接入范围：

- Flutter/Dart 播放业务对独占链路的选择、调用、状态消费和共享输出回退。
- Android USB 权限、设备识别、插拔、Audio Interface claim 和生命周期。
- Kotlin 独占会话、解码线程、端点/alt 选择、UAC 时钟、音量事务和诊断。
- JNI 与 C++17 核心，包括解码、DSD、UAC、quirk、音量、PCM 分包和 USBDEVFS ISO 传输。
- 本地文件、增长中的云端缓存文件、暂停、seek、热切歌、缓冲 telemetry 和设备拔出交接。

不包含：

- 任何固定 UI、页面导航、布局、颜色、动画或文案。
- 要求原作者照搬 `audio_output_settings_layer.dart`、状态胶囊或音量浮层。
- iOS、Windows、macOS 或 Linux 桌面 USB 后端。平台无关 C++ 核心可复用，但当前传输仍是 Android/Linux USBDEVFS。
- 未经真机证据验证的新 DAC 私有控制协议。

## 2. 最终架构和代码边界

```text
Dart 播放业务
  ├─ 判断是否尝试独占、准备文件、保存播放代际
  ├─ UsbAudioService / MethodChannel
  └─ 失败或拔出后交接共享输出
                     ↓
MainActivity
  ├─ USB 权限、插拔、MethodChannel
  └─ UsbExclusiveAudioEngine
       ├─ Kotlin：会话、线程、MediaCodec、USB 控制传输、策略
       ├─ JNI：类型与句柄边界
       └─ C++
            ├─ 平台无关：FLAC/WavPack、DSD、UAC、quirk、音量、PCM 分包
            └─ Android/Linux：USBDEVFS ISO URB 与反馈
                     ↓
                  USB DAC
```

边界原则：

- C++ 负责稳定、可对拍的计算和底层 ISO 传输。
- Kotlin 保留 Android 对象、线程、USB 控制传输、会话状态机和失败策略。
- Dart 负责播放器业务、当前曲目代际、共享/独占交接和产品层设置。
- UI 只消费接口状态，不是独占链路依赖。

## 3. 接入前检查

从最新上游主线创建独立分支：

```powershell
git fetch origin
git switch -c usb-exclusive-integration origin/main
git status --short --branch
```

开始前确认：

1. 工作区干净，没有原作者未提交修改。
2. Android `minSdk` 不低于当前项目的 26，或已评估 USB/JNI API 的兼容差异。
3. Flutter、Android Gradle Plugin、NDK 和 CMake 能完成现有上游基线构建。
4. 接入分支不同时混入 UI 重做、播放器重构或依赖升级。
5. 已决定是否保留 Kotlin package `com.afalphy.sylvakru`。修改 package 时必须同步 JNI 符号。
6. 已核对 libFLAC 与 WavPack 的许可证和 `third_party/*/SYLVAKRU_SOURCE` 来源记录。

建议先记录基线：

```powershell
F:\software\flutter_3.44.5\bin\flutter.bat pub get
F:\software\flutter_3.44.5\bin\flutter.bat analyze
Set-Location android
.\gradlew.bat app:testDebugUnitTest
Set-Location ..
```

若基线本身失败，先记录与独占无关的既有错误；不要用 USB 修改掩盖它。

## 4. 文件清单与依赖关系

### 4.1 原样引入的 native 文件

复制整个 `android/app/src/main/cpp/` 中以下内容：

```text
CMakeLists.txt
flac_decoder.{h,cpp} + flac_decoder_jni.cpp
wavpack_decoder.{h,cpp} + wavpack_decoder_jni.cpp
usb_dsd.{h,cpp} + usb_dsd_jni.cpp
usb_uac.{h,cpp} + usb_uac_jni.cpp
usb_dac_quirks.{h,cpp} + usb_dac_quirks_jni.cpp
usb_volume_protocol.{h,cpp} + usb_volume_protocol_jni.cpp
usb_pcm_packetizer.{h,cpp} + usb_pcm_packetizer_jni.cpp
usb_exclusive_engine.cpp
tests/*.cpp
testdata/*.flac
```

同时复制完整第三方目录：

```text
third_party/flac-1.5.0/
third_party/wavpack-5.9.0/
```

不要只复制 public headers；当前 CMake 从源码构建两个第三方静态库。

### 4.2 原样或少量改包名引入的 Kotlin 文件

```text
UsbDacQuirks.kt
UsbDiagnostics.kt
UsbDsd.kt
UsbExclusiveAudioEngine.kt
UsbFlacDecoder.kt
UsbNativePcmDecoder.kt
UsbPreferredMixer.kt
UsbStreamTransition.kt
UsbUac.kt
UsbVolumeProtocol.kt
UsbWavPackDecoder.kt
```

测试：

```text
UsbDacQuirksTest.kt
UsbHardwareVolumeTest.kt
UsbStreamTransitionTest.kt
UsbVolumeProtocolTest.kt
```

`UsbExclusiveAudioEngine.kt` 较大，但它承载当前真实会话策略。首次接入应保持行为等价，不要在移植过程中同时拆分类或改线程模型。

### 4.3 必须手工合并的 Android 文件

```text
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/.../MainActivity.kt
android/app/src/main/res/xml/usb_audio_device_filter.xml
android/app/src/main/assets/usb_dac_quirks.json
```

`MainActivity.kt` 只能按功能块合并：通道、引擎构造、权限 receiver、设备 callback、方法分发和销毁。不要整文件覆盖上游作者已有 Activity 逻辑。

### 4.4 必须手工合并的 Dart 业务文件

```text
lib/base/services/usb_audio_service.dart
lib/base/services/usb_audio_preferences.dart
lib/base/services/replay_gain.dart
lib/base/audio_handler.dart
test/usb_audio_service_test.dart
test/usb_audio_preferences_test.dart
test/usb_volume_safety_test.dart
test/replay_gain_test.dart
```

`usb_audio_service.dart` 可作为接口实现引入；`audio_handler.dart` 必须按上游当前播放流程手工接线，不能整文件替换。

### 4.5 不需要复制的 UI

基础接入不需要：

```text
lib/layer/audio_output_settings_layer.dart
lib/base/widgets/audio_output_panel.dart
lib/base/widgets/usb_exclusive_volume_overlay.dart
播放页状态胶囊、设置页 part 文件及其图片资源
```

原作者只需从 `UsbAudioService` 的状态 notifier 或等价状态流读取数据，自行设计 UI。若完全不展示状态，播放链路仍可工作。

## 5. 阶段一：NDK、CMake 与第三方库

### 文件

- `android/app/build.gradle.kts`
- `android/app/src/main/cpp/CMakeLists.txt`
- `third_party/flac-1.5.0/`
- `third_party/wavpack-5.9.0/`

### 接线

在 Android module 中保留 Flutter 提供的 NDK 版本，并增加：

```kotlin
android {
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17", "-Wall", "-Wextra")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}
```

不要在 Gradle 中写死 `abiFilters`。发布 arm64 由构建命令的 `--target-platform android-arm64` 控制，避免破坏模拟器和 split-per-abi。

CMake 当前关闭 libFLAC/WavPack 的 CLI、示例、安装和不需要的格式，静态链接到一个 Android 共享库。保留这些开关，避免把工具程序和无用依赖带入 APK。WavPack DSD 与 legacy 文件当前明确不支持。

### 成功标准

- Gradle 能配置 CMake 3.22.1。
- `FLAC::FLAC`、`WavPack::WavPack` 和各 `sylvakru_*` 静态目标可生成。
- APK 中只有应用需要的 `libsylvakru_usb_exclusive.so`，不额外发布 CLI。

### 失败停止点

如果第三方源码路径、CMake 目标名或 NDK API 检测失败，先停在构建层；不要继续接 JNI 以免把链接错误误判为接口错误。

## 6. 阶段二：C++ 核心与 native 测试

### 文件

引入 §4.1 所列 C++ 核心、测试和 fixture。

### 接线

先构建平台无关静态目标，不切换 Kotlin 生产路径。模块职责：

| 目标 | 职责 |
| --- | --- |
| `sylvakru_flac_decoder` | 保真实位深的 FLAC 解码 |
| `sylvakru_wavpack_decoder` | PCM WavPack 解码 |
| `sylvakru_usb_dsd` | DSF/DFF、DoP、Native DSD |
| `sylvakru_usb_uac` | UAC 原始描述符解析 |
| `sylvakru_usb_dac_quirks` | quirk 键和采样率选择 |
| `sylvakru_usb_volume_protocol` | 音量数值、HID 报文和安全决策 |
| `sylvakru_usb_pcm_packetizer` | PCM 转换、增益、淡入淡出和包长 |

主机测试示例：

```powershell
cmake -S android/app/src/main/cpp -B build/native-host `
  -DSYLVAKRU_BUILD_HOST_TESTS=ON `
  -DSYLVAKRU_FLAC_TESTDATA_DIR="$PWD/android/app/src/main/cpp/testdata"
cmake --build build/native-host --config Debug
```

当前 CMake 生成独立可执行测试，不注册 `ctest`。按生成器路径运行：

```text
flac_decoder_test
wavpack_decoder_test
usb_volume_protocol_test
usb_dsd_test
usb_uac_test
usb_pcm_packetizer_test
usb_dac_quirks_test
```

若主机工具链无法构建第三方库，可通过 Android/NDK 生成这些测试可执行文件后推送真机运行；不要把 `usb_exclusive_engine.cpp` 加入主机目标，它依赖 Android/Linux USBDEVFS 与 JNI。

### 成功标准

- 七个 native 测试程序全部返回 0。
- DSD 测试覆盖 `0x69`、DoP marker/carry、Native 端序和 seek 对齐。
- 音量与 PCM 测试逐数值对拍，不因语言迁移改变一 bit。

### 失败停止点

任何纯逻辑对拍失败都必须先修复；不能靠 Kotlin 补偿 C++ 行为差异后继续接线。

## 7. 阶段三：JNI 与 Kotlin 薄包装

### 文件

- 全部 `*_jni.cpp`
- `UsbExclusiveAudioEngine.kt` 顶部 native objects
- `UsbDsd.kt`、`UsbUac.kt`、两个 decoder 和协议包装

### 接线

1. CMake 只在 `ANDROID` 下生成 `sylvakru_usb_exclusive` 共享库。
2. 将所有 JNI `.cpp` 加入同一共享目标并链接七个静态核心和 Android log。
3. Kotlin 包装统一加载 `sylvakru_usb_exclusive`。
4. 句柄类在打开失败、正常结束、异常和硬关闭路径都必须销毁句柄。
5. 对照 [接口参考](usb-exclusive-native-api.md) 固定数组布局和哨兵值。

包名规则：当前符号是 `Java_com_afalphy_sylvakru_*`。只改 `applicationId` 不影响 JNI；移动 Kotlin package 或改 object 名会使链接运行时出现 `UnsatisfiedLinkError`，必须同步改所有 JNI 符号或改用动态注册。

### 成功标准

- arm64 Android 构建能链接共享库。
- 启动应用不会出现 `dlopen` 或 `UnsatisfiedLinkError`。
- decoder/reader 的 create、open、read、seek、close 冒烟测试通过。

### 失败停止点

若加载库或 JNI 符号失败，停在本阶段；不要开始 USB 权限和端点调试。

## 8. 阶段四：USB 权限、设备生命周期与 MethodChannel

### 文件

- `AndroidManifest.xml`
- `res/xml/usb_audio_device_filter.xml`
- `MainActivity.kt`
- `usb_audio_service.dart`

### 接线

Manifest 至少需要音频/前台播放相关权限，并给 Activity 增加 USB attach intent 和 filter：

```xml
<intent-filter>
    <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"/>
</intent-filter>
<meta-data
    android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
    android:resource="@xml/usb_audio_device_filter"/>
```

filter 的通用入口是：

```xml
<usb-device class="1" />
```

只有设备没有在 device level 声明 Audio Class，且已经验证确需补充时，才增加精确 VID/PID fallback。

`MainActivity` 合并以下功能块：

1. 创建通道 `com.afalphy.sylvakru/usb_audio`。
2. 创建 `UsbExclusiveAudioEngine`，将三个 emitter 转发到 Dart。
3. 注册 MethodChannel 方法分发。
4. 注册/注销 USB permission receiver。
5. 注册/注销 `AudioDeviceCallback`，插拔时刷新状态；拔出时调用引擎失效处理。
6. `onDestroy` 调用 `release()`。

权限请求必须保存 pending result 和目标设备，并在 receiver 中只完成一次。Android 13 以上使用带 class 的 `getParcelableExtra`。

Dart 侧接入 `UsbAudioService`，按 `playbackId` 过滤迟到事件。UI 可以不存在，但业务层必须监听活动状态和设备移除，否则失败后无法安全回退。

### 成功标准

- 插入 UAC DAC 后能枚举设备并请求权限。
- 授权结果只完成一次，拒绝授权返回明确状态。
- 拔出设备会使独占状态失活，而不是让暂停线程永久占用会话。

### 失败停止点

未获得权限、没有 Audio Interface、没有等时 OUT 端点时，应停在能力诊断并保持共享输出，不能进入 worker。

## 9. 阶段五：基础 PCM 独占

### 文件

- `UsbExclusiveAudioEngine.kt`
- `UsbUac.kt`
- `usb_uac.*`
- `usb_pcm_packetizer.*`
- `usb_exclusive_engine.cpp`

### 接线

基础路径：

```text
WAV/audio-raw 或 MediaCodec PCM
  → PcmIsoPacketizer（Kotlin 缓冲/节奏 + C++ 计算）
  → UsbExclusiveNative.writeIsoPackets
  → USBDEVFS ISO OUT
```

顺序：

1. 从 raw descriptors 解析 AS 格式、Feature Unit 和 UAC2 clock source。
2. 从 `UsbDevice` 接口/端点枚举等时 OUT 和可选 feedback IN。
3. 按采样率、声道、源位深、subslot 和 maxPacket 选择 alt。
4. claim interface，设置 UAC1 端点或 UAC2 clock source 的采样率。
5. `nativeOpen` 复制 fd、设置 altsetting 并启动反馈。
6. packetizer 计算槽位转换和每包帧数，按目标水位提交 URB。
7. 定期发布位置、状态和 telemetry。

PCM 不做采样率转换。找不到完全匹配的安全输出时，回退共享路径。位深自动选择规则为源一致优先，其次向上最近，再向下最近；无可用位深才失败。

### 成功标准

- 44.1k/16-bit 双声道 FLAC/WAV 能稳定出声。
- DAC 显示采样率与源一致，feedback 约等于名义每包帧数。
- 暂停/恢复无爆音，seek 后位置正确。

### 失败停止点

出现变调、持续噪声或 feedback 与名义值成倍偏差时，先修时钟/端点；不要继续接 DSD。

## 10. 阶段六：FLAC、WavPack 与系统解码格式

### 文件

- `UsbFlacDecoder.kt` / `flac_decoder.*`
- `UsbWavPackDecoder.kt` / `wavpack_decoder.*`
- `UsbNativePcmDecoder.kt`
- `UsbExclusiveAudioEngine.kt`

### 接线

- 完整本地 FLAC 优先走 libFLAC，输出 S32LE 容器并保留 16/20/24/32 有效位深。
- 完整 PCM WavPack 走 libwavpack；浮点、DSD WavPack 和 legacy 文件明确回退共享输出。
- WAV/audio-raw 和系统可解码的 mp3/m4a/aac/ogg/opus 等使用 `MediaExtractor + MediaCodec`。
- 进入独占前先保守探测 decoder，避免 worker 启动后才异步失败造成无声。
- 完整文件的 decoder seek 失败必须报告错误；不能静默从头播放。

### 成功标准

- 24-bit FLAC 状态中的 `sourceBitDepth/decodedBitDepth` 保持 24，不被厂商 MediaCodec 压成 16。
- WavPack PCM 能 seek，unsupported WavPack 安全回退。
- 系统有损格式只有在 `MediaCodecList.findDecoderForFormat` 成功时进入独占。

### 失败停止点

任何格式无法预检或解码时只回退该格式，不要让它破坏已通过的 PCM 基线。

## 11. 阶段七：DSD、DoP 与 Native DSD

### 文件

- `UsbDsd.kt`
- `usb_dsd.*` / `usb_dsd_jni.cpp`
- `UsbExclusiveAudioEngine.kt`
- `usb_dac_quirks.json`

### 接线

```text
DSF/DFF
  → DsdFileReader（统一 MSB-first 声道交错）
      ├─ DopPacketizer：2 DSD 字节 + 0x05/0xFA marker
      └─ NativeDsdPacketizer：u8/u16le/u32le/u32be
  → PcmIsoPacketizer（unity、只做槽位对齐）
  → ISO OUT
```

三条不可破坏规则：

1. DSD 静音只能用 `0x69`，不能用零。
2. DoP/Native DSD 不得应用数字音量、ReplayGain、抖动、重采样或其它 DSP。
3. 时钟 SET_CUR 使用容器帧率：DoP=`DSD rate÷16`；Native=`DSD rate÷8÷subslot bytes`。

DoP 需要 24/32-bit PCM alt；描述符无法直接声明 DoP，使用硬性带宽条件和 quirk。Native 优先使用精确 quirk `nativeDsd.format`，否则从 RAW_DATA alt subslot 推断。Native 失败先降级 DoP；DoP 也失败再回退共享 PCM。

DSD 编码器提升到会话级，写线程与空窗静音线程互斥使用。暂停、seek、热切歌和短空窗必须保持 ISO 流连续。不得在 DSD 会话随意 `flushOutput`。

### 成功标准

- DSF/DFF 能识别速率、声道、时长和 seek 对齐。
- DoP DSD64 时 DAC 进入 DSD 模式，marker 相位连续。
- 有 RAW_DATA/quirk 的设备能按正确排列进入 Native；失败自动降级且状态有原因。
- 暂停、seek、连续切歌时 DAC 指示灯不退出 DSD 模式。

### 失败停止点

任何排列试验都必须低音量且一次只改一个 quirk 字段。全幅噪声立即停止，不能靠 DSP 修正 DSD。

## 12. 阶段八：数字音量与硬件音量

### 文件

- `UsbVolumeProtocol.kt`
- `usb_volume_protocol.*` / JNI
- `UsbExclusiveAudioEngine.kt`
- `usb_audio_preferences.dart`
- `replay_gain.dart`

### 接线

音量模式：

| 模式 | PCM | DSD |
| --- | --- | --- |
| `digital` | C++ packetizer Q16 增益 | 禁止修改码流，无安全硬件能力时暂停/拒绝 |
| `dac` | 标准 UAC 或精确厂商协议 | 只有协议和 quirk 明确支持时使用 |
| `auto` | 硬件可验证则硬件，否则数字 | 只接受可验证、允许 DSD 的硬件路径 |
| `raw` | unity 原始数字电平 | 原始 DSD |

标准 UAC Feature Unit 使用 GET/RANGE、SET 和逐声道 readback；多声道任何一步失败都回滚。私有 HID/vendor 协议只有精确 VID/PID quirk 才能启用。

统一数值：

- 线性增益 Q16.16，`65536=1.0`。
- ReplayGain 为 milli-dB。
- DSD 补偿只允许写明确的硬件寄存器，不改 DoP marker 或 DSD payload。

硬件状态必须来自实际 readback。write-only 要明确标记，不能把请求值冒充 DAC 实际值。DSD 无可信旧值、写入不完整或恢复失败时，宁可暂停也不能冒险升音量。

### 成功标准

- PCM 数字音量 0/25/50/100% 数值和声道正确。
- 标准 UAC 写后读回一致；失败回滚不造成左右失衡。
- 数字/硬件切换用短斜坡，无瞬间满音量。
- DAC 主动事件只更新业务音量，不再次写回形成环路。

### 失败停止点

硬件协议证据不足时保持数字音量或本地系统音量，不能猜 request、寄存器或 report layout。

## 13. 阶段九：云端增长文件、缓冲与热切换

### 文件

- `audio_handler.dart`
- `usb_audio_service.dart`
- `UsbExclusiveAudioEngine.kt` 中 `GrowingFileDataSource` 和 worker 路径
- 云端缓存/下载服务的现有接入点

### 接线

1. 云端下载写入稳定的 `.part` 文件，同一文件只允许一个写入者。
2. 达到约 10 秒起播水位且下载速度可持续时，用 `streaming=true` 启动独占。
3. 传入 `totalBytes` 估计，让 `MediaExtractor` 能 seek 到未下载区。
4. PCM 数据未跟上时发布 buffering 并等待；DSD 数据未跟上时发送 `0x69` 静音。
5. 当前文件尾不等于真实 EOF：每约 80ms 重探已下载长度，可被 stop/pause/new seek 打断。
6. 达不到水位或下载速度不足时，及时回退共享流式输出。

热切换按旧/新 `UsbStreamSignature` 决策：参数相同可保留会话；参数变化需要双端静音和 DAC 重锁；预检失败时不能先破坏旧会话。`playbackId` 防止旧 worker 结束事件影响新曲。

PCM 与 DSD 的 seek/切歌默认都不丢在途 URB；强制 flush 会瞬断 ISO 流产生小爆音。代价是新位置声音可能延迟一个目标水位，这是连续性的取舍。

### 成功标准

- 增长文件读到当前下载末尾不会误报 completed 或自动跳歌。
- seek 到未下载区能进入 buffering，下载推进后继续。
- 同参数连播不重 claim/设 alt/配时钟。
- 连续切歌不会让旧状态覆盖新 `playbackId`。

### 失败停止点

若缓存层无法保证单写入者、文件路径稳定或长度可观测，先禁用流式独占，只对完整缓存文件启用独占。

## 14. 阶段十：诊断、失败回退与业务层交接

### 文件

- `UsbDiagnostics.kt`
- `MainActivity.kt` 诊断收集
- `usb_audio_service.dart`
- `audio_handler.dart`

### 接线

诊断至少包含：设备指纹、raw descriptors、AS 格式、输出候选、时钟源、quirk 命中、硬件音量探测、最近会话选择、feedback、URB/欠载统计和最终播放状态。

业务层回退顺序：

1. 记录独占最终状态和最后可信位置。
2. 使本地独占代际失效，避免迟到事件重新接管。
3. 调用 `releaseExclusiveDevice` 或确认 native 已硬关。
4. 恢复共享输出独立音量和 ReplayGain。
5. 重新打开共享播放器并 seek 到可信位置。
6. 只有用户原本处于播放状态时才恢复播放。

自然播放完成与异常中断必须区分：自然完成走播放队列下一首；异常中断走共享输出交接。用户主动 stop 不应自动恢复共享播放。

### 成功标准

- 每个失败状态都带可诊断 `message`。
- USB 拔出不会自动从手机扬声器突然出声；先安全暂停，再由业务策略决定恢复。
- 诊断报告能解释实际 alt、时钟、音量和回退原因。

### 失败停止点

如果业务层无法区分自然完成、用户停止和异常中断，先不要自动恢复播放，只安全暂停并保留位置。

## 15. 构建与自动测试

使用项目固定 Flutter：

```powershell
F:\software\flutter_3.44.5\bin\flutter.bat pub get
F:\software\flutter_3.44.5\bin\flutter.bat gen-l10n
F:\software\flutter_3.44.5\bin\flutter.bat analyze
F:\software\flutter_3.44.5\bin\flutter.bat test
```

Android JVM 测试：

```powershell
Set-Location android
.\gradlew.bat app:testDebugUnitTest
Set-Location ..
```

默认只构建 arm64 profile 包验证 JNI：

```powershell
F:\software\flutter_3.44.5\bin\flutter.bat build apk --profile --target-platform android-arm64
```

Release 验证：

```powershell
F:\software\flutter_3.44.5\bin\flutter.bat build apk --release --target-platform android-arm64
```

文案未变化时 `gen-l10n` 主要用于确认合并没有破坏现有生成链；不要提交无关 generated plugin 噪声。

## 16. 真机验收矩阵

按顺序验收，前一步失败就停止后续高风险项目：

| 顺序 | 场景 | 通过标准 |
| --- | --- | --- |
| 1 | USB 授权/拒绝/重连 | 无重复 result、无崩溃、状态正确 |
| 2 | PCM 44.1k/16-bit | 正常出声，采样率正确 |
| 3 | PCM 48/96/192k 与 24/32-bit | 无变调，端点/位深正确，欠载不增长 |
| 4 | 暂停/恢复/seek/连续切歌 | 无明显爆音，位置正确 |
| 5 | 本地 FLAC/WavPack/系统有损格式 | 位深和失败回退符合预期 |
| 6 | DoP DSD64 | DAC 进入 DSD，暂停和 seek 不掉模式 |
| 7 | DoP 设备上限 | 超限明确拒绝或回退 |
| 8 | Native DSD | 仅 RAW_DATA/精确 quirk 启用，排列正确 |
| 9 | PCM 数字音量 | 0/25/50/100%，无溢出和声道错误 |
| 10 | 硬件音量 | 低音量开始，SET/readback/实际响度闭环 |
| 11 | DAC 外置按钮 | 主动事件正确，App 不回写成环 |
| 12 | 增长文件/弱网/未下载 seek | buffering 后续播，不误跳歌 |
| 13 | 拔出/重插 | 安全暂停、保位置、资源释放、可恢复 |
| 14 | 后台/熄屏/系统回收 | 前台服务和音量键行为符合产品策略 |

自动测试通过不能替代第 1–14 项真机结论。报告中必须分别标注。

## 17. 常见接入错误

| 现象 | 常见原因 | 处理 |
| --- | --- | --- |
| `UnsatisfiedLinkError` | Kotlin package/object 与静态 JNI 符号不一致 | 对照接口参考同步符号或动态注册 |
| CMake 找不到 FLAC/WavPack | 只复制头文件或 third_party 相对路径改变 | 复制完整源码并修正唯一 CMake 入口 |
| 独占进入后无声 | 未预检 decoder、alt 不匹配或时钟未接受 | 从能力/时钟/feedback 顺序定位 |
| 声音变调 | SET_CUR 值错误或反馈单位解析错误 | 使用容器帧率，对照名义 frames/packet |
| DoP 全幅白噪声 | 数据被音量/DSP 修改或设备不支持 | unity 透传；必要时 `dop.supported:false` |
| Native 全幅噪声 | `u32le/u32be/u16le/u8` 排列错误 | 低音量、精确 quirk、一次只试一个变量 |
| DSD 暂停/切歌掉模式 | 发送 0、停止 ISO 或 flush 在途 URB | 发送 `0x69`，保持会话级 encoder 和 filler |
| seek 到云端未下载区直接跳歌 | 把增长文件当前末尾当真实 EOF | `streaming/totalBytes/canReadAt` 联合处理 |
| 硬件音量显示成功但响度不变 | 把返回长度或目标值当验证 | 必须 readback + 实际响度闭环 |
| 快速音量导致左右不一致 | 多包/多声道事务未串行或失败未回滚 | 单事务协调器、保存可信旧值、完整回滚 |
| 拔出后状态仍活动 | 暂停 worker 不再触发 IO 错误 | 主动设备 callback 使会话失效 |
| 退出独占突然满音量 | 未先建立 PCM 数字衰减 | 按现有平滑交接顺序恢复硬件 unity |

## 18. 合入建议

不要一次提交整套移植。推荐按可验证能力拆分：

1. `build(android): 接入 USB 独占 native 构建与第三方解码库`
2. `test(usb): 引入 native 纯逻辑对拍测试`
3. `feat(usb): 接入 JNI 与 Kotlin native 包装`
4. `feat(usb): 接入基础 PCM 独占传输`
5. `feat(usb): 接入 FLAC 与 WavPack 原生解码`
6. `feat(usb): 接入 DoP 与 Native DSD`
7. `feat(usb): 接入独占音量和安全回退`
8. `feat(usb): 接入增长文件、热切换与 telemetry`
9. `docs(usb): 补充独占诊断和设备适配资料`

每次提交前检查：

```powershell
git status
git diff --check
git diff --stat
git diff
```

先在原作者集成分支完成自动测试和至少一台 UAC DAC 的逐阶段验收，再合入主线。若某一阶段尚未完成，保持上一个阶段可构建、可回退，不要用未接线的设置或 UI 冒充功能已经可用。
