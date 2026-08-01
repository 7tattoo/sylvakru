# USB 独占完整接入资料设计

## 目标

为原作者提供一套不依赖当前开发分支提交历史、可从最新 `origin/main` 手工移植的 USB 独占完整接入资料。资料以接口、数据流、生命周期、安全边界和验证步骤为中心，不规定 UI 页面、视觉组件或交互设计。

## 受众与前提

- 主要读者是熟悉当前 sylvakru Flutter/Android 工程的原作者。
- 接入目标是完整 USB 独占能力，而不是只复用若干 C++ 算法文件。
- 原作者可以自行设计设置入口、状态展示和音量界面。
- 文档必须区分当前真实代码、历史设计记录、自动测试结论和仍需真机验证的行为。

## 当前资料问题

- `README.md` 仍宣传已删除的固定采样率设置。
- `docs/dac-adaptation-guide.md` 仍把 DSD、UAC、quirk、音量协议和 PCM 分包的部分核心职责写在 Kotlin，未反映 C++ 下沉后的边界。
- `docs/usb-output-settings-status.md` 仍列出已删除入口与旧占位项，且缺少 native 核心现状。
- 缺少从 Dart 播放调度到 USB DAC 的完整手工接入顺序。
- 缺少集中说明 C++、JNI、Kotlin 和 MethodChannel 接口合同的参考资料。

## 交付物

### 新增资料

1. `docs/usb-exclusive-integration-guide.md`
   - 面向完整功能移植。
   - 从构建依赖开始，按可独立验证的阶段接入。
   - 列出每阶段涉及文件、接线位置、成功标准、回退和常见错误。

2. `docs/usb-exclusive-native-api.md`
   - 集中记录 C++、JNI、Kotlin native 包装和 MethodChannel 合同。
   - 说明参数、返回值、数组布局、哨兵值、线程、所有权和句柄生命周期。

### 修订资料

- `README.md`：删除过期能力，补充接入与接口资料入口。
- `docs/dac-adaptation-guide.md`：更新架构图、文件职责和测试归属，保留已验证的 DAC 取证、quirk 与安全规则。
- `docs/usb-output-settings-status.md`：删除不存在的入口和占位项，改为当前真实能力与 native 边界状态。

### 不修改资料

- `docs/superpowers/plans/` 和既有历史设计稿保持原样。它们记录当时的实施过程，不作为当前接口合同。

## 接入架构

```text
播放业务层（Dart）
  ├─ 独占资格判断、文件准备和共享输出回退
  ├─ MethodChannel 请求
  └─ 状态、传输和硬件音量事件
            ↓
Android 接入层（Kotlin）
  ├─ USB 权限、设备识别与插拔
  ├─ 会话生命周期、线程与缓冲策略
  ├─ altsetting、UAC 时钟和硬件音量事务
  └─ JNI 薄包装
            ↓
C++ 核心
  ├─ FLAC/WavPack 解码
  ├─ DSD 容器读取与 DoP/Native 打包
  ├─ UAC 描述符解析与 quirk 匹配
  ├─ 音量协议和 PCM 分包纯计算
  └─ Android USBDEVFS ISO URB 传输
            ↓
USB DAC
```

UI 不在该架构的必要依赖中。上层只需根据接口状态自行展示或完全不展示。

## 接入阶段

1. 配置 NDK、CMake、C++17、libFLAC 和 libwavpack。
2. 引入平台无关 C++ 静态库、Android 传输实现和 native 测试。
3. 引入 JNI 共享库与 Kotlin 薄包装，固定包名或同步修改 JNI 符号。
4. 接入 Android USB 权限、设备识别、插拔和 MethodChannel。
5. 打通基础 PCM 独占、UAC alt 选择、时钟和 USBDEVFS 传输。
6. 接入 FLAC、WavPack 和系统 MediaExtractor/MediaCodec 解码格式。
7. 接入 DSF/DFF、DoP、Native DSD、静音填充和不断流规则。
8. 接入 PCM 数字音量、标准 UAC 音量和已验证厂商协议。
9. 接入增长文件、云端缓存水位、telemetry、seek 和热切歌。
10. 接入诊断报告、完整失败回退和真机验收矩阵。

每个阶段都必须可独立构建或验证，不要求一次性复制全部功能后再排错。

## 接口资料组织

接口参考按以下四层排列：

1. Dart/MethodChannel 方法和事件。
2. Kotlin `UsbExclusiveAudioEngine` 与 native 包装对象。
3. JNI 符号、数组布局、空值和哨兵约定。
4. C++ 头文件公开 API、依赖和测试覆盖。

对句柄式对象统一说明：创建方拥有句柄；使用线程；关闭与销毁时机；无效句柄行为；异常和 EOF 的表达方式。对无状态函数统一说明输入域、返回哨兵及与 Kotlin 类型的映射。

## 必须固定的安全边界

- native `String?` 返回中，`null` 表示成功，非空字符串表示错误。
- 句柄必须成对创建和销毁；会话关闭与对象销毁不能混为一谈。
- DSD 静音字节只能是 `0x69`。
- DoP/Native DSD 数据不得进入软件音量、ReplayGain、抖动、重采样或其它 DSP。
- DSD 和连续 PCM 的切歌/seek 不得随意 `flushOutput`，避免瞬断 ISO 流。
- UAC 时钟使用容器帧率，不使用数据字节率。
- PCM 增益使用 Q16.16；ReplayGain 使用千分之一 dB。
- JNI 数组字段顺序和枚举序号属于接口 ABI，不得无迁移地重排。
- 私有硬件音量协议只允许精确 VID/PID quirk 启用。
- readback 失败时不得把请求目标冒充实际硬件值；DSD 无可信音量时保持暂停或拒绝启动。
- `usb_exclusive_engine.cpp` 依赖 Android/Linux `usbdevice_fs`；其余标明平台无关的计算模块才可直接用于桌面后端。

## 错误与回退设计

- 任一接入阶段失败都应返回结构化状态或明确错误字符串，不让播放线程静默挂死。
- 独占资格、权限、端点、时钟、解码或传输失败时，上层负责退出未完成会话并回退共享输出。
- Native DSD 判定失败先降级 DoP；DoP 不可用再回退共享 PCM。
- PCM 硬件音量失败可回退数字音量；DSD 不允许通过修改码流回退软件音量。
- 设备拔出时先使旧会话失效、保留可信位置，再由上层决定是否恢复共享输出。

## 验证设计

- C++ 主机或 NDK 测试验证解码、DSD、UAC、quirk、音量协议和 PCM 分包纯逻辑。
- Android JVM 测试验证仍留在 Kotlin 的会话决策、序列化和状态转换。
- Android arm64 构建验证 JNI 符号、第三方库和共享库链接。
- 真机矩阵验证 USB 权限、PCM 各采样率、反馈端点、FLAC/WavPack、DoP、Native DSD、暂停/seek/切歌、音量、拔插、后台和增长文件。
- 文档不得把“自动测试通过”写成“DAC 真机已验证”。

## 完成标准

- 原作者无需阅读当前分支的历史提交或旧实施计划即可确定要复制的文件和接线顺序。
- 所有对外接口均有参数、返回、生命周期和失败语义。
- UI 完全可替换，业务层只依赖方法和事件合同。
- 现有公开资料不再声称核心仍由纯 Kotlin 实现，也不再宣传已删除设置。
- 文档中的文件名、方法名、CMake 目标和测试命令均能在当前代码中核对。
