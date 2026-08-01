# USB 独占接口参考

本文集中说明 USB 独占链路对接时需要保持稳定的 Dart、MethodChannel、Kotlin、JNI 与 C++ 接口。它描述的是当前源码合同，不规定设置页、状态胶囊、音量浮层或其它 UI。

完整移植步骤见 [USB 独占完整接入指南](usb-exclusive-integration-guide.md)，设备适配见 [USB DAC 适配指南](dac-adaptation-guide.md)。

## 1. 接口分层与稳定性

```text
Dart 播放业务
  └─ UsbAudioService
       └─ MethodChannel: com.afalphy.sylvakru/usb_audio
            └─ MainActivity
                 └─ UsbExclusiveAudioEngine（Kotlin 会话/策略）
                      ├─ Usb*Native（JNI 薄包装）
                      └─ sylvakru_usb_exclusive（C++ 共享库）
                           ├─ 平台无关静态核心
                           └─ Android/Linux USBDEVFS 传输
```

稳定性按以下原则理解：

- MethodChannel 的方法名、事件名和 Map 字段是 Dart/Android 之间的运行时合同。
- Kotlin `external fun` 的类名、包名、方法名和参数签名共同决定 JNI 符号。
- JNI 返回数组的字段顺序、枚举序号和哨兵值属于 ABI，不能只改一侧。
- C++ 头文件是平台无关核心的源码级 API；目前不承诺二进制 ABI 稳定。
- `usb_exclusive_engine.cpp` 直接依赖 Linux `usbdevice_fs`，只属于 Android/Linux 传输后端。

## 2. MethodChannel 调用合同

通道名：

```text
com.afalphy.sylvakru/usb_audio
```

### 2.1 状态与系统首选输出

| 方法 | 参数 | 返回 | 说明 |
| --- | --- | --- | --- |
| `getStatus` | 无 | `UsbAudioStatus` Map | 获取当前 USB/系统音频状态 |
| `applyPreferredOutput` | `deviceId?`、`sampleRate?`、`encoding`、`bitPerfect` | `UsbAudioStatus` Map | 设置系统共享输出偏好；它不是 USBDEVFS 独占 |
| `clearPreferredOutput` | 无 | `UsbAudioStatus` Map | 清除系统共享输出偏好 |
| `probeExclusiveAccess` | 无 | `UsbExclusiveProbeResult` Map | 检查设备、权限、Audio Interface 和 claim 能力；可能先触发权限请求 |
| `getExclusiveCapabilities` | 无 | `UsbExclusiveCapability` Map | 返回当前设备可见的等时 OUT 端点能力摘要 |

`UsbAudioStatus` 主要字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `supported` | `bool` | 当前平台是否支持 Android USB 音频接入 |
| `androidSdk` | `int` | Android SDK 级别 |
| `activeDeviceId` | `int?` | 当前系统音频设备 ID |
| `preferredApplied` | `bool` | 系统首选输出请求是否已应用 |
| `preferredSampleRate` | `int?` | 请求的系统输出采样率 |
| `preferredEncoding` | `String?` | 请求的系统 PCM 编码 |
| `preferredBitPerfect` | `bool` | 是否请求系统 bit-perfect 属性 |
| `outputDeviceName` | `String?` | 当前系统输出设备名 |
| `outputSampleRate` | `int?` | 当前系统输出采样率 |
| `outputEncoding` | `String?` | 当前系统输出编码 |
| `manufacturerName/productName` | `String?` | USB 设备厂商和产品名 |
| `vendorId/productId` | `int?` | USB VID/PID |
| `devices` | `List<Map>` | 枚举到的 USB 音频设备摘要 |
| `message` | `String?` | 状态或失败说明 |

`UsbExclusiveProbeResult` 字段为 `supported`、`permissionGranted`、`deviceName`、`deviceId`、`audioInterfaceCount`、`claimedInterfaceCount`、`rawDescriptorLength` 和 `message`。

`UsbExclusiveCapability` 字段为 `available`、`permissionGranted`、`deviceName`、`deviceId`、`interfaceNumber`、`alternateSetting`、`endpointAddress`、`maxPacketSize`、`sampleRates`、`bitDepths`、`channelCounts` 和 `message`。它是建链前摘要；最终 alt、位深和反馈端点以实际会话选择为准。

### 2.2 独占会话控制

| 方法 | 参数 | 返回 | 说明 |
| --- | --- | --- | --- |
| `startExclusivePlayback` | 见下表 | `UsbExclusivePlaybackState` Map | 新建或热替换独占播放 |
| `pauseExclusivePlayback` | 无 | 状态 Map | 暂停供数；DSD 会继续发送合法静音 |
| `resumeExclusivePlayback` | 无 | 状态 Map | 恢复；DSD 会先过硬件音量安全门 |
| `seekExclusivePlayback` | `positionMs` | 状态 Map | 提交异步 seek 目标 |
| `stopExclusivePlayback` | 无 | 状态 Map | 停止当前曲目，允许短时间保留可热复用会话 |
| `releaseExclusiveDevice` | 无 | 状态 Map | 停止并立即释放 USB 会话和设备资源 |
| `setExclusiveTargetBufferMs` | `targetBufferMs` | 状态 Map | 目标范围由 Kotlin 钳位到 50–1000ms |
| `setExclusiveVolume` | 见 §2.4 | `null` | 异步提交音量目标 |

`startExclusivePlayback` 参数：

| 字段 | 类型 | 必需 | 含义 |
| --- | --- | --- | --- |
| `playbackId` | `String` | 是 | 业务层播放代际 ID；用于丢弃旧会话迟到事件 |
| `filePath` | `String` | 是 | Android 可读取的本地文件或增长中的 `.part` 路径 |
| `title` | `String?` | 否 | 诊断标题，不参与解码 |
| `sourceFormat` | `String?` | 否 | 小写格式提示，如 `flac`、`wv`、`dsf`、`dff` |
| `sampleRate` | `int?` | PCM 建议提供 | 源采样率；引擎仍会从实际解码格式核对 |
| `bitDepth` | `int?` | PCM 建议提供 | 源有效位深提示 |
| `dsdMode` | `String?` | DSD 必需 | `dop` 或 `native`；PCM 为 `null` |
| `volumeGainQ16` | `int` | 是 | 用户线性增益，0–65536 |
| `replayGainMilliDb` | `int` | 是 | ReplayGain，千分之一 dB |
| `volumeMode` | `String` | 是 | `auto`、`dac`、`digital` 或 `raw` |
| `dsdGainCompensationDb` | `int` | 是 | DSD 硬件补偿，钳位到 -12–6dB |
| `smoothHandoff` | `bool` | 是 | PCM 数字/硬件音量是否平滑交接 |
| `targetBufferMs` | `int?` | 否 | 当前前台/后台目标缓冲 |
| `startPaused` | `bool` | 是 | 建链后是否保持暂停 |
| `replaceActive` | `bool` | 否 | 是否替换当前活动曲目；用于热切歌错误发布门控 |
| `streaming` | `bool` | 是 | 文件是否仍在增长 |
| `totalBytes` | `int?` | 流式建议提供 | 完整文件大小估计；让 `MediaExtractor` 能 seek 到尚未下载区 |

### 2.3 播放状态

`start/pause/resume/seek/stop/release` 均返回同一状态结构，异步更新也使用它：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `playbackId` | `String?` | 状态所属播放代际 |
| `active` | `bool` | 独占会话是否活动 |
| `playing` | `bool` | 业务播放状态 |
| `buffering` | `bool` | 增长文件未跟上或正在垫静音 |
| `positionMs` | `int` | 当前可信播放位置 |
| `durationMs` | `int?` | 总时长 |
| `sampleRate` | `int?` | 实际输出帧率；DSD 模式是容器帧率 |
| `bitDepth` | `int?` | 兼容字段，当前通常对应输出位深 |
| `sourceBitDepth` | `int?` | 源文件有效位深 |
| `decodedBitDepth` | `int?` | 解码器实际输出有效位深 |
| `usbBitDepth` | `int?` | USB subslot/端点有效位深 |
| `bitPerfect` | `bool?` | 当前链路是否满足位完美条件 |
| `format` | `String?` | 当前输出格式/模式 |
| `hardwareVolumeActive` | `bool` | 真实硬件音量路径是否生效 |
| `digitalVolumeActive` | `bool` | PCM 数字音量是否生效 |
| `hardwareVolumeWriteOnly` | `bool` | 只能写、无法可信回读 |
| `hardwareVolumeReadbackVerified` | `bool` | 本次硬件目标是否完成可信回读 |
| `hardwareVolumeSyncPending` | `bool` | 音量事务是否仍在同步 |
| `hardwareVolumeFrozen` | `bool` | 回读异常时是否冻结在可信目标 |
| `hardwareVolumeProtocol` | `String?` | `uac1`、`uac2` 或精确厂商协议名 |
| `hardwareVolumeRaw` | `int?` | 实际硬件原始值；不是请求值替代品 |
| `hardwareVolumeGainQ16` | `int?` | 实际硬件值换算出的线性增益 |
| `replayGainMilliDb` | `int` | 当前合成的 ReplayGain |
| `message` | `String?` | 成功、回退、暂停或失败原因 |

业务层必须按 `playbackId` 丢弃旧播放的迟到状态。`active=false` 不自动等于“用户主动停止”；应结合 `message` 和本地意图决定是否回退共享输出。

### 2.4 音量、诊断与 quirk

`setExclusiveVolume` 参数：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `gainQ16` | `int` | 用户目标线性增益，0–65536 |
| `replayGainMilliDb` | `int` | 当前曲目的 ReplayGain |
| `mode` | `String` | `auto`、`dac`、`digital`、`raw` |
| `dsdGainCompensationDb` | `int` | -12–6dB，只用于有明确能力的硬件协议 |
| `smoothHandoff` | `bool` | PCM 音量路径切换是否做斜坡 |

`getUsbDiagnosticsReport` 无参数，返回 Android 原生诊断 Map；Dart 可把它与偏好、播放状态和最近日志组合成 Markdown。

`importUsbDacQuirks` 参数为 `json`，返回 `{ok: bool, error: String?}`。导入成功后应重连设备再验证；私有协议必须精确匹配 VID/PID。

## 3. MethodChannel 事件合同

Android 使用同一通道反向调用 Dart：

| 事件 | 参数 | 处理规则 |
| --- | --- | --- |
| `onUsbAudioDeviceEvent` | `{type, deviceId, status}` | `type` 为 `added/removed`，刷新设备状态并触发插拔交接 |
| `onUsbExclusiveStateChanged` | 播放状态 Map | 当前主要状态事件，按 `playbackId` 过滤 |
| `onUsbExclusivePosition` | 播放状态 Map | 兼容事件，按完整状态解析 |
| `onUsbExclusiveError` | 播放状态 Map | 兼容事件，按完整状态解析 |
| `onUsbTransportTelemetryChanged` | telemetry Map | 更新传输水位和欠载状态 |
| `onUsbHardwareVolumeChanged` | 硬件音量事件 Map | DAC 主动变化同步到业务音量，不得再次回写形成反馈环 |
| `onUsbExclusiveVolumeKey` | `{direction}` | 可选手机物理键事件，方向非零时转成业务音量步进 |

telemetry 字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `active` | `bool` | 传输会话是否活动 |
| `bufferLevelMs` | `int` | 当前 native 待提交/在途队列估算水位 |
| `minimumBufferLevelMs` | `int?` | 本会话非零最低水位 |
| `targetBufferMs` | `int?` | 当前目标水位 |
| `isoPacketCount` | `int` | ISO 包统计 |
| `pendingUrbs` | `int` | 在途输出 URB 数量 |
| `underrunCount` | `int` | 欠载计数 |
| `lastUnderrunAtMs` | `int?` | 最近欠载时刻 |
| `updatedAtMs` | `int` | 单调时钟更新时间 |

硬件音量事件字段为 `playbackId`、`gainQ16`、`leftRaw`、`rightRaw`、`protocol`、`isDsd`、`replayGainMilliDb` 和 `dsdGainCompensationDb`。Dart 当前要求 `gainQ16` 位于 0–65536，且字符串字段非空，否则丢弃事件。

## 4. Kotlin 会话接口

### 4.1 `UsbExclusiveAudioEngine`

构造：

```kotlin
UsbExclusiveAudioEngine(
    context,
    emitState,
    emitTelemetry,
    emitHardwareVolume,
)
```

公开业务方法：

| 方法 | 线程/返回 | 说明 |
| --- | --- | --- |
| `capabilities(usbManager, device)` | 同步 Map | 只做建链前能力摘要 |
| `start(usbManager, device, arguments)` | 同步返回首状态，后台线程继续工作 | 解析请求、选端点、配时钟、建解码和传输线程 |
| `pause()` / `resume()` | 同步状态 | 修改会话供数状态；恢复受 DSD 音量门控 |
| `seek(positionMs)` | 同步确认，worker 异步执行 | 只发布新目标，不在调用线程做重解码 |
| `setVolume(...)` | 无返回，单线程协调器异步执行 | 合并快速目标，串行硬件事务 |
| `setTargetBufferMs(value)` | 状态 Map | 立即更新 native 最大在途 URB 目标 |
| `stop()` | 状态 Map | 停曲但允许热复用会话和空窗填充 |
| `release()` | 状态 Map | 强制拆除会话 |
| `handleUsbAudioDeviceRemoved()` | `Map?` | 设备确已消失时使旧会话失效并保留位置 |

`UsbExclusiveAudioEngine` 是 Android 会话协调器，不应被下沉成纯 C++：它依赖 `UsbManager`、`UsbDeviceConnection`、`MediaExtractor`、`MediaCodec`、线程、Handler、MethodChannel 状态和 Android USB 控制传输。

### 4.2 Kotlin native 包装

| JNI 包装对象 | Kotlin 业务包装/用途 |
| --- | --- |
| `UsbExclusiveNative` | 进程内持有一个传输句柄；`open/close` 切换会话 |
| `UsbPcmNative` | 每个 `PcmIsoPacketizer` 独占一个计算句柄 |
| `UsbFlacNative` | `UsbFlacDecoder` 的句柄、direct buffer 读取和 seek |
| `UsbWavPackNative` | `UsbWavPackDecoder` 的句柄、direct buffer 读取和 seek |
| `UsbDsdNative` | `DsdFileReader`、`DopPacketizer`、`NativeDsdPacketizer` 的句柄和无状态格式映射 |
| `UsbUacNative` | UAC 原始描述符的四个无状态解析入口 |
| `UsbDacQuirksNative` | quirk 键匹配和位完美采样率选择 |
| `UsbVolumeNative` | 增益、位深、iBasso 报文与安全决策的无状态入口 |

FLAC/WavPack decoder 和 DSD reader/encoder 都是单线程、`Closeable`、必须可靠关闭。两个 PCM decoder 输出交错 S32LE direct buffer。

## 5. JNI 通用约定

共享库名：

```kotlin
System.loadLibrary("sylvakru_usb_exclusive")
```

CMake 目标名为 `sylvakru_usb_exclusive`。当前 Kotlin 包为 `com.afalphy.sylvakru`，因此静态 JNI 符号以此开头：

```text
Java_com_afalphy_sylvakru_<Object>_<method>
```

原作者若修改 applicationId 但保留 Kotlin package，无需改 JNI；若修改 native 包装对象所在 package 或类名，必须同步修改所有 C++ 符号，或改用 `RegisterNatives`。ProGuard/R8 也不得重命名持有静态 JNI 方法的类和方法。

通用规则：

- `jlong` 保存不透明 C++ 指针，只能交还给同一对象族。
- 句柄 `0` 或无效句柄按各 JNI 的安全默认值处理，但上层不应依赖无效句柄继续工作。
- `String?` 错误返回：`null` 为成功，非空为错误。
- 读解码器返回帧数；负值表示解码错误，`0 + endOfStream=true` 才映射为 Kotlin EOF `-1`。
- `ByteBuffer` 必须是 direct buffer，容量至少为 `capacityFrames × channels × 4`。
- 所有 `*GainQ16` 和反馈包长 Q16 值均为 Q16.16 定点数；`65536` 表示 `1.0`，不得当作百分比或原始 DAC 音量值。
- 所有 `*MilliDb` 值均以千分之一 dB 为单位；例如 `-6021` 表示 `-6.021 dB`。
- JNI 数组是扁平 ABI，修改宽度或顺序必须同时修改 C++ 生成端、Kotlin 解析端和测试。

### 5.1 固定数组布局

| 接口 | 数组布局 |
| --- | --- |
| FLAC/WavPack `streamInfo` | `[sampleRate, channels, validBitsPerSample, totalFrames]` |
| DSD `readerInfo` | `[sampleRate, channels, durationMs]` |
| PCM `nextPacketBytes` | `[packetBytes, outputFeedbackQ16, nominalQ16, state]`，state 0/1/2=无反馈/接受/拒绝 |
| USB transport `nativeTransportTelemetry` | `[pendingIsoPackets, totalIsoPackets, pendingOutputUrbs, isoErrorCount]` |
| UAC `parseStreamingFormats` | 每项 10 个 Int：interface、alt、protocol、terminalLink、formatType、channels、subslotSize、bitResolution、bmFormats、hasBmFormats；缺失值按 Kotlin 解析约定编码 |
| UAC `findClockSource` | `[hasClockSource, terminalLink, clockSourceId]` |
| UAC `parseVolumeFeatures` | 每项 6 个 Int：uac2、controlInterface、unitId、sourceId、channel、writable |
| iBasso 目标 | `[baseRaw, dsdRaw]` |

UAC 的精确缺失值和 boolean 编码以 `usb_uac_jni.cpp` 与 Kotlin 解析函数为同一真值源；不要在其它层自行发明第二套结构。

## 6. C++ 模块 API

### 6.1 `flac_decoder.h`

目标：`sylvakru_flac_decoder`，依赖 `FLAC::FLAC`。

`FlacDecoder` 提供 `open`、`streamInfo`、`readFrames`、`seekToFrame`、`close`。输出为交错 `int32_t` 容器，`valid_bits_per_sample` 记录真实有效位深。对象不可复制，只供一个独占解码线程使用。

结果类型：`FlacResult`/`FlacReadResult` 用 `ok()` 判断；读取结果同时携带帧数、EOS 和错误文本。测试：`cpp/tests/flac_decoder_test.cpp`。

### 6.2 `wavpack_decoder.h`

目标：`sylvakru_wavpack_decoder`，依赖 `WavPack::WavPack`。

`WavPackDecoder` 接口与 FLAC 对齐，输出同为交错 `int32_t`。当前构建关闭 WavPack DSD 和 legacy `<4.0` 支持，打开这些文件应明确失败并由上层回退共享输出。测试：`cpp/tests/wavpack_decoder_test.cpp`。

### 6.3 `usb_dsd.h`

目标：`sylvakru_usb_dsd`，平台无关。

- `DsdFileReader`：读取 DSF/DFF，统一输出 MSB-first、逐字节声道交错数据；`streaming=true` 时配合 `canReadAt` 区分暂时没下载到和真实 EOF。
- `DopPacketizer`：每声道每帧装两个 DSD 字节并交替写 `0x05/0xFA` 标记。
- `NativeDsdPacketizer`：按 `u8/u16le/u32le/u32be` 重排，不修改 DSD bit。
- `nativeDsdBytesPerSample`：未知格式返回 `0`，Kotlin 映射为 `null`。
- `kDsdSilenceByte`：固定 `0x69`。

`DsdStreamEncoder::encode` 保留不足一帧 carry；`drain` 用 `0x69` 补齐；DoP seek 需要 `reset` 恢复标记相位。测试：`cpp/tests/usb_dsd_test.cpp`。

### 6.4 `usb_uac.h`

目标：`sylvakru_usb_uac`，平台无关，只解析原始配置描述符。

- `parseUacStreamingFormats`：合并同一 `(interface, alt)` 的 AS_GENERAL 和 Type-I 信息。
- `findUac2ClockSource`：沿 terminal 查时钟源，找不到映射时回退第一个时钟源。
- `parseUacVolumeFeatures`：解析带音量控制的 UAC1/UAC2 Feature Unit 通道。
- `parseUacOutputTerminalSources`：提取输出端子 source ID。

数值 `-1` 表示字段缺失。`bm_formats` D31 表示 RAW_DATA/native DSD。`protocol` 字段保留原 Kotlin 的历史偏移，仅用于诊断，不应参与端点决策。测试：`cpp/tests/usb_uac_test.cpp`。

### 6.5 `usb_dac_quirks.h`

目标：`sylvakru_usb_dac_quirks`，平台无关。

- `dacQuirkKey`：生成 `0x%04x:0x%04x` 或 `0x%04x:*`。
- `matchDacQuirkIndex`：按输入 keys 顺序执行精确 VID/PID，再厂商通配匹配；返回命中下标，未命中 `-1`。
- `chooseBitPerfectMixerSampleRate`：指定请求时必须精确命中；未指定时取最大正值；无结果 `-1`。

JSON、asset、override 和 `DacQuirk` 字段解析仍在 Kotlin。测试：`cpp/tests/usb_dac_quirks_test.cpp`。

### 6.6 `usb_volume_protocol.h`

目标：`sylvakru_usb_volume_protocol`，平台无关。

它包含 PCM 自动位深选择、Q16 增益与 ReplayGain 合成、iBasso 非线性音量表、HID 报文构造/路由、读回验证、reader 恢复、事务节流和主动事件换算。协议选择、USB 实际读写、会话 generation、DSD 安全文案和健康状态机仍在 Kotlin。

关键常量和哨兵：

- `kIbassoUnityGainQ16 = 65536`。
- 可空 Kotlin Int 以 `hasValue/value` 或 C++ 空指针表达。
- `preferredAutoPcmBitDepth` 无结果返回 `0`。
- `IbassoVolumeVerificationAction` 与 `IbassoReaderRecoveryAction` 按枚举序号跨 JNI，禁止重排。

任何数值或决策修改必须先通过 `cpp/tests/usb_volume_protocol_test.cpp`；“回读失灵只允许只降不升、无可信值宁可暂停”的边界不能放宽。

### 6.7 `usb_pcm_packetizer.h`

目标：`sylvakru_usb_pcm_packetizer`，平台无关。

`PcmPacketizerCore` 负责：

- 源位深到 USB subslot 的符号扩展和高位对齐；
- Q16 数字增益；
- 暂停恢复淡入和切换尾部淡出；
- 反馈 Q16 包长余数状态机；
- 捕获最后一帧用于无爆音切换。

`process=false` 表示满刻度、无需转换或淡入，调用方应沿用原缓冲；`true` 时使用输出 vector。`reset` 清包长余数和最后帧，不清淡入进度。DoP 只能以 unity 增益进入，并仅允许槽位对齐。测试：`cpp/tests/usb_pcm_packetizer_test.cpp`。

### 6.8 `usb_exclusive_engine.cpp`

目标：Android 共享库 `sylvakru_usb_exclusive` 的传输部分。依赖 `jni.h`、`android/log.h`、`linux/usbdevice_fs.h`、`ioctl` 和文件描述符。

`Transport` 句柄持有复制后的 USB fd、接口/端点、反馈值、在途 URB 和统计。主要 JNI 操作：

- `nativeOpen`：`dup(fd)`，可选 claim，执行 `USBDEVFS_SETINTERFACE`，启动反馈 URB。
- `nativeWritePcm`：按固定 ISO 包大小分批提交。
- `nativeWriteIsoPackets`：一次提交最多 16 个变长 ISO 包。
- `nativeFeedbackFramesPerPacketQ16`：读取最近有效反馈。
- `nativeTransportTelemetry`：回收已完成 URB 并返回统计数组。
- `nativeSetIsoPacketSize`：钳位到端点 maxPacket。
- `nativeSetMaxPendingOutputUrbs`：钳位到 8–512。
- `nativeFlushOutput`：丢弃/回收在途输出；只能在策略明确允许时调用。
- `nativeClose`：关闭当前会话；`nativeDestroy` 才销毁句柄对象。

传输对象内部用 mutex 串行化。Kotlin 仍负责包内容、包长决策、目标水位和调用节奏。

## 7. 所有权、线程与生命周期

| 对象 | 创建方 | 使用线程 | 释放 |
| --- | --- | --- | --- |
| `UsbExclusiveNative` transport | Kotlin object 初始化 | USB worker/telemetry 调用，经 native mutex 串行化 | 会话 `close`；进程对象理论上 `destroy`，当前 object 持有到进程结束 |
| `PcmPacketizerCore` | 每个 Kotlin `PcmIsoPacketizer` | 所属写线程 | `UsbPcmNative.destroy` |
| FLAC/WavPack decoder | 对应 Kotlin decoder `open` | 单个解码线程 | `close/destroy`，可重复 close |
| `DsdFileReader` | DSD start | 单个 DSD worker | `close/readerDestroy` |
| DoP/Native encoder | DSD 会话 | 写线程与空窗填充线程互斥使用 | 会话硬关闭时 `close/encoderDestroy` |
| UAC/quirk/volume 无状态函数 | 调用即用 | 由 Kotlin 调用方保证业务顺序 | 无句柄 |

热切歌时，曲目 worker 可以更换，但 USB 会话、DSD 编码相位和 PCM packetizer 可能继续存在。不得因为一首曲目结束就无条件销毁会话级对象。

## 8. 错误、EOF 与哨兵值

| 场景 | 表达 |
| --- | --- |
| native 操作成功 | `String? == null` |
| native 操作失败 | 非空英文错误字符串；进入诊断和上层回退 |
| FLAC/WavPack 正常 EOF | native `0 frames + endOfStream=true`，Kotlin 映射 `readFrames=-1` |
| FLAC/WavPack 解码失败 | native 负返回并由 `lastError` 提供原因，Kotlin 抛 `IOException` |
| DSD EOF | `DsdFileReader.read=-1` |
| 增长文件暂时无数据 | 调用 `canReadAt=false`，不得当 EOF 跳歌 |
| quirk/采样率未命中 | `-1` |
| native DSD 未知格式 | `0`，Kotlin 映射 `null` |
| UAC 字段缺失 | `-1` 或专用 has 标志 |
| 无反馈 | Q16 值 `0`，PCM 包长回落名义速率 |

独占失败的最终状态必须 `active=false` 并带 `message`；业务层停止未完成会话后再切回共享输出。不得让错误只停留在 logcat 而状态仍显示活动。

## 9. ABI 变更检查清单

修改 native 接口前逐项确认：

- [ ] Kotlin 包名、object/class 名和 `external fun` 名是否变化。
- [ ] JNI 符号和签名是否同步。
- [ ] CMake 共享库名是否仍与 `System.loadLibrary` 一致。
- [ ] 句柄创建、关闭、销毁是否仍严格配对。
- [ ] 扁平数组长度、顺序、boolean/nullable 编码是否同步。
- [ ] 跨 JNI 枚举顺序是否保持不变。
- [ ] direct `ByteBuffer` 的样本格式和容量是否保持一致。
- [ ] `null=成功`、EOF 和各哨兵值是否保持一致。
- [ ] DSD `0x69`、不进 DSP、不随意 flush 等安全边界是否仍满足。
- [ ] 对应 C++ 测试、Kotlin 测试和 arm64 JNI 链接是否通过。
