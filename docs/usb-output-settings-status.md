# USB 独占当前接入状态

本文记录当前 USB 独占播放链路的真实实现边界和验证级别。它不再按旧设置页逐项列举，也不把已经删除的设置或历史占位项写成现有能力。

源码移植见 [USB 独占完整接入指南](usb-exclusive-integration-guide.md)，接口字段见 [USB 独占接口参考](usb-exclusive-native-api.md)，设备适配见 [USB DAC 适配指南](dac-adaptation-guide.md)。

## 状态口径

- **已接入**：生产路径已经调用该实现。
- **自动测试覆盖**：存在 C++、Kotlin 或 Dart 回归测试；不等于 DAC 真机已验证。
- **有设备证据**：至少有项目现有 DAC 日志或实播证据。
- **仍需逐设备验证**：能力与描述符、固件或厂商协议相关，不能从代码存在推断所有 DAC 可用。

## Native 与平台边界

| 模块 | 当前状态 | 实现边界 | 验证 |
| --- | --- | --- | --- |
| Android native 构建 | 已接入 | CMake 3.22.1、C++17；libFLAC 1.5.0 与 WavPack 5.9.0 源码静态链接到 `sylvakru_usb_exclusive` | arm64 NDK/Gradle 构建路径已接入 |
| USBDEVFS ISO 传输 | 已接入 | `usb_exclusive_engine.cpp` 以句柄保存 fd、端点、反馈、URB 和统计；依赖 Android/Linux，不是平台无关模块 | 现有实播链路使用；仍需不同 USB 控制器回归 |
| FLAC 解码 | 已接入 | `flac_decoder.cpp` 输出交错 S32LE，保留 16/20/24/32 有效位深 | C++ fixture 测试；本地 FLAC 生产路径使用 |
| WavPack 解码 | 已接入 | `wavpack_decoder.cpp` 解码 PCM WavPack；DSD WavPack、浮点和 legacy 不支持时回退 | C++ 往返测试；生产路径使用 |
| DSD 容器与打包 | 已接入 | `usb_dsd.cpp` 负责 DSF/DFF、DoP 和 Native DSD；`UsbDsd.kt` 是 JNI 薄包装 | `usb_dsd_test.cpp` 对拍；DSD 实播仍需逐 DAC 验证 |
| UAC 描述符解析 | 已接入 | `usb_uac.cpp` 负责 AS 格式、时钟源、Feature Unit 和输出端子纯解析；Kotlin 做结构化映射和控制传输 | `usb_uac_test.cpp` 对拍；不同 UAC1/UAC2 描述符仍需设备回归 |
| DAC quirk 匹配 | 已接入 | C++ 负责键匹配和位完美采样率选择；Kotlin 负责 JSON、asset、override 和字段解析 | C++ 匹配测试 + Kotlin JSON 测试 |
| 音量协议核心 | 已接入 | C++ 负责 Q16/milli-dB、自动位深、iBasso 报文和安全决策；Kotlin 负责 USB 读写、事务、generation 和健康状态 | C++ 数值/报文测试 + Kotlin 会话测试；私有协议只对精确设备有效 |
| PCM 分包计算 | 已接入 | `usb_pcm_packetizer.cpp` 负责槽位转换、数字增益、淡入淡出和反馈包长；Kotlin 负责缓冲、worker 和 URB 节奏 | `usb_pcm_packetizer_test.cpp` 对拍，包含 DoP unity 红线 |
| JNI 边界 | 已接入 | 所有句柄、扁平数组和无状态函数统一进入 `sylvakru_usb_exclusive` | arm64 链接验证；ABI 变化需双侧同步 |

## Android 与业务链路

| 能力 | 当前状态 | 说明 |
| --- | --- | --- |
| USB attach 与设备识别 | 已接入 | Manifest 注册 `USB_DEVICE_ATTACHED`；filter 匹配 Audio Class，并为已验证的设备提供精确 fallback |
| USB 权限与能力探测 | 已接入 | `probeExclusiveAccess()` 检查权限、Audio Interface、claim 和 raw descriptors；`getExclusiveCapabilities()` 返回端点摘要 |
| MethodChannel | 已接入 | 通道提供状态、启动、暂停、恢复、seek、停止、释放、音量、缓冲、诊断和 quirk 导入；反向发布状态、telemetry、插拔和硬件音量事件 |
| 播放代际隔离 | 已接入 | `playbackId` 用于丢弃旧 worker 和旧会话迟到事件，避免切歌后旧状态覆盖新曲 |
| 设备拔出交接 | 已接入 | Android 主动使会话失效并保留位置；Dart 区分自然完成、用户停止和异常中断，再决定共享输出恢复 |
| 共享输出回退 | 已接入 | 权限、端点、采样率、解码、DSD 判定或 native 传输失败时退出未完成会话，由业务层回退共享播放器 |
| 前后台缓冲目标 | 已接入 | Dart 生命周期选择目标水位，Kotlin 换算最大在途 URB，native 提供实时在途统计 |
| 后台保活 | 策略已接入 | 前台媒体服务和偏好已接入；最终存活仍受各厂商电池策略影响 |
| 播放后释放 USB | 已接入 | `stop()` 可短时保留热复用会话，`release()` 强制释放；产品策略可选择停止后何时释放 |

## 播放格式与传输行为

| 能力 | 当前状态 | 说明 |
| --- | --- | --- |
| PCM 独占 | 已接入 | 不做 SRC；按源采样率、声道、有效位深、subslot 和 maxPacket 选择安全 alt，无法精确匹配则回退 |
| PCM 位深模式 | 已接入 | 自动模式优先源一致，其次向上最近，再向下最近；也支持用户选择 16/24/32-bit 输出偏好 |
| 完整本地 FLAC | 已接入 | libFLAC 保真实位深，避免部分系统解码器把 24-bit 压成 16-bit |
| 完整本地 WavPack | 已接入 | libwavpack 支持当前 PCM 范围；不支持类型在进入独占前回退 |
| 系统可解码格式 | 已接入 | WAV/audio-raw 直通；mp3/m4a/aac/ogg/opus 等只有 MediaCodec 预检成功才进入独占 |
| DoP | 已接入 | DSD rate÷16；需要 24/32-bit alt；marker 为 `0x05/0xFA`，静音 payload 为 `0x69` |
| Native DSD | 已接入 | RAW_DATA alt 或精确 quirk 指定 `u8/u16le/u32le/u32be`；失败先降 DoP，再回退共享输出 |
| DSD 不断流 | 已接入 | 编码器会话级复用，暂停/空窗发送 `0x69`，seek/切歌不随意 flush 在途 URB |
| 同参数热切歌 | 已接入 | 设备、采样率、声道、位深和 DSD 类别兼容时保留接口、alt 和时钟，避免 DAC 重锁 |
| 跨参数切换 | 已接入 | 预检后用双端静音和预滚保护重配置；旧会话在替换预检完成前保持有效 |

## 音量与 ReplayGain

| 能力 | 当前状态 | 说明 |
| --- | --- | --- |
| PCM 数字音量 | 已接入 | C++ packetizer 在源位深域应用 Q16.16 线性增益；DoP/Native DSD 永不进入该路径 |
| ReplayGain | 已接入 | 音轨/专辑选择、fallback 和 peak headroom 在共享与独占路径统一；native 接收 milli-dB |
| 标准 UAC 音量 | 已接入 | Feature Unit 探测、GET/RANGE、SET、逐声道 readback 和失败回滚；状态只发布实际读回 |
| 厂商音量协议 | 已接入精确协议 | 由 `UsbVolumeProtocol` 能力和精确 VID/PID quirk 选择；当前 iBasso 协议不能按厂商 VID 泛化 |
| DAC 主动音量事件 | 已接入代码 | 区分命令响应、迟到响应和 unsolicited event，去抖后同步业务音量，不回写形成环路；仍需对应设备逐项验收 |
| 手机物理音量键 | 已接入 | 前台 Activity 和后台 MediaSession 根据实际硬件/数字音量接管；退出独占恢复本地系统音量 |
| DSD 音量安全门 | 已接入 | 只有协议声明且 quirk 允许的硬件增益可用于 DSD；无可信 readback 时冻结、暂停或拒绝恢复，不修改 DSD 码流 |
| 音量平滑交接 | 已接入 | PCM 在数字/硬件路径间使用短斜坡；退出硬件模式先建立数字衰减再恢复 DAC unity |

## 云端增长文件与 telemetry

| 能力 | 当前状态 | 说明 |
| --- | --- | --- |
| 云端完整缓存独占 | 已接入 | Navidrome/WebDAV/Emby 等来源缓存为本地完整文件后使用相同独占路径 |
| 增长文件起播 | 已接入 | 达到目标水位且下载速度可持续时，以 `streaming=true` 打开稳定 `.part` 文件 |
| 未下载区 seek | 已接入 | `totalBytes` 让 extractor 可定位；当前文件尾不当真实 EOF，约 80ms 重探下载进度 |
| 弱网回退 | 已接入 | 起播期限内水位不足时回退共享流式输出；独占 worker 不静默等待到无声 |
| 传输 telemetry | 已接入 | native 返回 pending/total ISO 包、在途 URB 和错误；Kotlin 换算水位、最低值、欠载和目标后发布 Dart |
| 诊断报告 | 已接入 | 包含设备、描述符、解析、quirk、时钟、音量、会话选择、反馈、URB 和最终状态 |

## 仍需逐设备或系统验证

以下内容不能因为代码和自动测试存在就写成“所有设备已验证”：

1. 每台 DAC 的最高 PCM 采样率、位深和 feedback 格式。
2. DoP 支持上限与 Native DSD 字节排列。
3. 标准 Feature Unit 是否真实改变模拟响度，以及 DSD 是否经过同一硬件增益。
4. 私有 HID/vendor 协议的报文、readback 和外置按钮事件。
5. 不同手机 USB 控制器、Android 版本和厂商电池策略下的后台稳定性。
6. 弱网、缓存改名、服务端 Range 行为和长时间增长文件读取。
7. 拔插、暂停、连续切歌和跨采样率重锁时的实际爆音表现。

完成新设备验收时，应同时保存诊断报告、相关英文 logcat、原始描述符和最小精确 quirk，不得只记录“能出声”。
