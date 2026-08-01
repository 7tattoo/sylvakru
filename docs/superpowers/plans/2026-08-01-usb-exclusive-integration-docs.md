# USB 独占完整接入资料实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为原作者提供从最新上游主线手工移植完整 USB 独占功能的接入指南与接口资料，并修正现有文档中已经过期的 Kotlin/C++ 职责和已删除设置。

**Architecture:** 新增一份端到端接入指南和一份分层接口参考；现有 DAC 适配指南继续负责设备取证与 quirk，状态文档继续负责当前能力真值，README 只保留准确概览和资料入口。所有资料排除 UI 实现，只描述业务、平台和 native 接口。

**Tech Stack:** Markdown、Flutter/Dart MethodChannel、Android Kotlin、JNI、C++17、CMake 3.22.1、Android NDK、USBDEVFS、libFLAC 1.5.0、libwavpack 5.9.0。

---

### Task 1: 编写 C++、JNI、Kotlin 与 MethodChannel 接口参考

**Files:**
- Create: `docs/usb-exclusive-native-api.md`
- Read: `android/app/src/main/cpp/*.h`
- Read: `android/app/src/main/cpp/*_jni.cpp`
- Read: `android/app/src/main/kotlin/com/afalphy/sylvakru/Usb*.kt`
- Read: `lib/base/services/usb_audio_service.dart`

- [ ] **Step 1: 建立接口参考目录**

按以下固定顺序创建章节：

```markdown
# USB 独占接口参考
## 1. 接口分层与稳定性
## 2. MethodChannel 调用合同
## 3. MethodChannel 事件合同
## 4. Kotlin 会话接口
## 5. JNI 通用约定
## 6. C++ 模块 API
## 7. 所有权、线程与生命周期
## 8. 错误、EOF 与哨兵值
## 9. ABI 变更检查清单
```

- [ ] **Step 2: 记录 MethodChannel 方法与事件**

逐项记录当前通道 `com.afalphy.sylvakru/usb_audio` 的方法：`getStatus`、`applyPreferredOutput`、`clearPreferredOutput`、`probeExclusiveAccess`、`getExclusiveCapabilities`、`startExclusivePlayback`、`pauseExclusivePlayback`、`resumeExclusivePlayback`、`setExclusiveTargetBufferMs`、`setExclusiveVolume`、`seekExclusivePlayback`、`stopExclusivePlayback`、`releaseExclusiveDevice`、`getUsbDiagnosticsReport`、`importUsbDacQuirks`。

逐项记录事件：`onUsbExclusiveStateChanged`、`onUsbTransportTelemetryChanged`、`onUsbHardwareVolumeChanged`。为 `startExclusivePlayback` 参数和播放状态字段提供完整表格，字段名以 `UsbExclusivePlaybackRequest.toMap()` 和 `UsbExclusivePlaybackState.fromMap()` 为准。

- [ ] **Step 3: 记录 JNI 与 native 句柄合同**

覆盖以下包装对象和符号族：

```text
UsbExclusiveNative / UsbPcmNative
UsbFlacNative / UsbWavPackNative
UsbDsdNative / UsbUacNative
UsbDacQuirksNative / UsbVolumeNative
```

明确包名变更会改变 `Java_com_afalphy_sylvakru_*` JNI 符号；`create/destroy` 必须配对；`nativeOpen/nativeClose` 是传输会话生命周期，不等于销毁传输对象；返回 `String?` 时 `null` 为成功。

- [ ] **Step 4: 记录 C++ 模块公开 API**

按头文件分别记录：

```text
flac_decoder.h
wavpack_decoder.h
usb_dsd.h
usb_uac.h
usb_dac_quirks.h
usb_volume_protocol.h
usb_pcm_packetizer.h
usb_exclusive_engine.cpp（Android/Linux 传输边界）
```

每个模块必须说明职责、公开类型/函数、输入输出、状态/哨兵、线程假设、平台依赖和对应测试程序。明确 `usb_exclusive_engine.cpp` 依赖 `linux/usbdevice_fs.h`，不是平台无关模块。

- [ ] **Step 5: 校验接口名与文档字段**

运行：

```powershell
rg -n "external fun|private external fun|System\.loadLibrary" android/app/src/main/kotlin/com/afalphy/sylvakru -g '*.kt'
rg -n "JNIEXPORT|Java_com_afalphy_sylvakru" android/app/src/main/cpp -g '*.cpp'
rg -n "startExclusivePlayback|onUsbExclusiveStateChanged|onUsbTransportTelemetryChanged|onUsbHardwareVolumeChanged" android/app/src/main/kotlin/com/afalphy/sylvakru/MainActivity.kt lib/base/services/usb_audio_service.dart
```

Expected: 文档列出的包装对象、JNI 符号族、调用方法和事件均能在源码命中；无文档虚构接口。

- [ ] **Step 6: 提交接口参考**

```powershell
git add docs/usb-exclusive-native-api.md
git commit -m "docs(usb): 添加独占接口参考"
```

### Task 2: 编写无 UI 的完整手工接入指南

**Files:**
- Create: `docs/usb-exclusive-integration-guide.md`
- Read: `android/app/build.gradle.kts`
- Read: `android/app/src/main/cpp/CMakeLists.txt`
- Read: `android/app/src/main/AndroidManifest.xml`
- Read: `android/app/src/main/kotlin/com/afalphy/sylvakru/MainActivity.kt`
- Read: `android/app/src/main/kotlin/com/afalphy/sylvakru/UsbExclusiveAudioEngine.kt`
- Read: `lib/base/audio_handler.dart`
- Read: `lib/base/services/usb_audio_service.dart`

- [ ] **Step 1: 建立接入指南目录**

使用以下章节：

```markdown
# USB 独占完整接入指南
## 1. 适用范围与非目标
## 2. 最终架构和代码边界
## 3. 接入前检查
## 4. 文件清单与依赖关系
## 5. 阶段一：NDK、CMake 与第三方库
## 6. 阶段二：C++ 核心与 native 测试
## 7. 阶段三：JNI 与 Kotlin 薄包装
## 8. 阶段四：USB 权限、设备生命周期与 MethodChannel
## 9. 阶段五：基础 PCM 独占
## 10. 阶段六：FLAC、WavPack 与系统解码格式
## 11. 阶段七：DSD、DoP 与 Native DSD
## 12. 阶段八：数字音量与硬件音量
## 13. 阶段九：云端增长文件、缓冲与热切换
## 14. 阶段十：诊断、失败回退与业务层交接
## 15. 构建与自动测试
## 16. 真机验收矩阵
## 17. 常见接入错误
## 18. 合入建议
```

- [ ] **Step 2: 写明文件复制清单和依赖顺序**

列出 C++ 源码/头文件/JNI、Kotlin 引擎与包装、Flutter service/播放调度、manifest/filter、quirk assets、libFLAC/libwavpack 和测试文件。明确 UI 文件不是必要依赖，`audio_output_settings_layer.dart`、状态胶囊和音量浮层无需复制。

- [ ] **Step 3: 写明十阶段接入步骤**

每阶段包含四部分：需要复制或修改的文件、接线动作、阶段成功标准、失败时停止点。PCM 必须先于 DSD；静态核心必须先于 JNI；JNI 必须先于 MethodChannel；硬件音量必须晚于基础播放链路。

- [ ] **Step 4: 固定不可破坏的音频安全规则**

指南必须明确：DSD 静音 `0x69`；DoP/Native 不进 DSP；容器帧率时钟；DSD/连续 PCM 不随意 flush；Q16.16 与 milli-dB；硬件读回诚实性；精确 VID/PID 私有协议；设备拔出和失败回退。

- [ ] **Step 5: 写明验证命令和预期**

包含固定 Flutter 路径和 arm64 默认构建：

```powershell
F:\software\flutter_3.44.5\bin\flutter.bat pub get
F:\software\flutter_3.44.5\bin\flutter.bat gen-l10n
F:\software\flutter_3.44.5\bin\flutter.bat analyze
Set-Location android
.\gradlew.bat app:testDebugUnitTest
Set-Location ..
F:\software\flutter_3.44.5\bin\flutter.bat build apk --profile --target-platform android-arm64
```

native 测试同时给出 CMake 开关 `SYLVAKRU_BUILD_HOST_TESTS=ON` 和测试目标名，说明 Android USB 传输目标只能在 Android 构建中链接。

- [ ] **Step 6: 提交接入指南**

```powershell
git add docs/usb-exclusive-integration-guide.md
git commit -m "docs(usb): 添加完整独占接入指南"
```

### Task 3: 修订 DAC 适配指南的 C++ 架构边界

**Files:**
- Modify: `docs/dac-adaptation-guide.md:30`
- Reference: `docs/usb-exclusive-native-api.md`

- [ ] **Step 1: 更新架构图**

把 DSD 读取/编码、PCM 分包计算、UAC 解析、quirk 匹配和音量协议数值核心标记为 C++；把 Kotlin 标记为会话、USB 控制传输、线程、缓冲、URB 节奏和策略胶水。把 USBDEVFS 传输标记为 Android/Linux 专用。

- [ ] **Step 2: 更新关键文件职责表**

补充 `usb_dsd.*`、`usb_uac.*`、`usb_dac_quirks.*`、`usb_volume_protocol.*`、`usb_pcm_packetizer.*` 和对应 JNI 文件。将 `UsbDsd.kt` 改为 JNI 薄包装，不再声称纯 Kotlin/JVM 测试覆盖。

- [ ] **Step 3: 更新测试归属和交叉链接**

说明下沉逻辑由 `cpp/tests/*_test.cpp` 对拍，仍留 Kotlin 的会话逻辑使用 JVM 测试；在开头链接完整接入指南和接口参考，不重复复制接口表。

- [ ] **Step 4: 搜索过期实现描述**

运行：

```powershell
rg -n "纯 Kotlin|JVM 单测|Kotlin PcmIsoPacketizer|从 Kotlin|留在 Kotlin|JNI" docs/dac-adaptation-guide.md
```

Expected: “从 Kotlin 下沉”只用于迁移历史说明；当前职责不再把已下沉模块描述成 Kotlin 实现。

- [ ] **Step 5: 提交适配指南修订**

```powershell
git add docs/dac-adaptation-guide.md
git commit -m "docs(usb): 更新 DAC 适配指南的 native 架构"
```

### Task 4: 重写当前状态真值并删除过期设置

**Files:**
- Modify: `docs/usb-output-settings-status.md`

- [ ] **Step 1: 删除不存在的功能描述**

删除固定采样率输出，以及位深兼容、采样率兼容、声道兼容、TPDF、延迟建链、USB 总线速度等已从当前页面移除的旧占位表述。不得把代码里仍存在的 PCM 位深模式误删。

- [ ] **Step 2: 增加 native 核心状态表**

按“构建/传输/解码/DSD/UAC/quirk/音量/PCM 分包/telemetry/诊断”记录当前真实职责和验证级别。区分平台无关 C++、Android 专用传输、Kotlin 策略和 Dart 业务调度。

- [ ] **Step 3: 保留仍准确的用户能力状态**

保留 DSD 模式、ReplayGain、硬件音量安全回退、DAC 双向同步、后台物理键、音量平滑、quirk、云端增长文件和 telemetry，但校正其中 C++/Kotlin 实现位置。

- [ ] **Step 4: 校验已删除设置不再出现**

运行：

```powershell
rg -n "固定采样率|位深兼容|采样率兼容|声道兼容|TPDF|延迟建立|总线速度" docs/usb-output-settings-status.md
```

Expected: 无输出。

- [ ] **Step 5: 提交状态文档修订**

```powershell
git add docs/usb-output-settings-status.md
git commit -m "docs(usb): 同步独占功能当前接入状态"
```

### Task 5: 修正 README 并建立资料导航

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 删除过期功能行**

删除“固定采样率 / 位深，可锁定输出格式”的功能行。保留“PCM 位深自动选择/模式”时必须与当前设置和引擎行为一致，不使用“固定采样率”措辞。

- [ ] **Step 2: 更新实现概览**

用一段简短文字说明性能与协议核心已下沉 C++，Kotlin 保留 Android 会话和策略；避免把整个独占引擎误写成纯 C++。

- [ ] **Step 3: 添加资料入口**

链接：

```markdown
- [完整接入指南](docs/usb-exclusive-integration-guide.md)
- [接口参考](docs/usb-exclusive-native-api.md)
- [DAC 适配指南](docs/dac-adaptation-guide.md)
- [当前接入状态](docs/usb-output-settings-status.md)
```

- [ ] **Step 4: 提交 README 修订**

```powershell
git add README.md
git commit -m "docs(usb): 更新独占功能概览与资料入口"
```

### Task 6: 全量交叉验证、推送与汇报

**Files:**
- Verify: `README.md`
- Verify: `docs/usb-exclusive-integration-guide.md`
- Verify: `docs/usb-exclusive-native-api.md`
- Verify: `docs/dac-adaptation-guide.md`
- Verify: `docs/usb-output-settings-status.md`

- [ ] **Step 1: 检查 Markdown 和 Git 差异**

```powershell
git status --short
git diff --check
git log -7 --oneline
```

Expected: 工作区干净；无空白错误；最近提交只包含本任务设计、计划和文档修订。

- [ ] **Step 2: 检查链接目标存在**

```powershell
@(
  'docs/usb-exclusive-integration-guide.md',
  'docs/usb-exclusive-native-api.md',
  'docs/dac-adaptation-guide.md',
  'docs/usb-output-settings-status.md'
) | ForEach-Object { if (-not (Test-Path $_)) { throw "Missing: $_" } }
```

Expected: 命令无错误退出。

- [ ] **Step 3: 检查过期表述和接口拼写**

```powershell
rg -n "固定采样率 / 位深|DSF/DFF 解析、DoP/native 编码器（纯 Kotlin" README.md docs
rg -n "UsbExclusiveNative|UsbPcmNative|UsbDsdNative|UsbUacNative|UsbDacQuirksNative|UsbVolumeNative" docs/usb-exclusive-native-api.md
```

Expected: 第一条无输出；第二条命中全部六类 native 包装对象。

- [ ] **Step 4: 重试远程获取并确认分支**

```powershell
git fetch origin
git fetch fork
git status --short --branch
git branch --show-current
```

Expected: 当前分支为 `usb-exclusive-clean`，工作区干净；若 GitHub 网络仍失败，如实记录，不修改历史。

- [ ] **Step 5: 推送当前分支**

```powershell
git push fork usb-exclusive-clean
```

Expected: `fork/usb-exclusive-clean` 更新到本任务最后一个提交；禁止强制推送。

- [ ] **Step 6: 完成汇报**

汇报必须包含修改文件、文档边界、用户可见变化、执行的验证、未执行的构建/真机验证、所有提交、推送分支，以及远程网络或已知限制。
