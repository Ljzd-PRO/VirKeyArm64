# VirKeyArm64 0.1.0.30 测试记录

日期：2026-09-30（Asia/Shanghai）。

## 结论

**本次 SC 样本的启动授权验收通过。** Parallels Windows 11 ARM64 中，原始 `C:\Program Files\SolidCAM2024\Solidcam\Solidcam.exe` 进入首次设置，确认后打开 SolidCAM Manager；第二次启动直接进入同一界面。没有修改应用或 Sentinel 用户态文件。

- [首次成功界面](evidence/guest-v30/SolidCAM-Manager.png)
- [第二次启动界面](evidence/guest-v30/SolidCAM-Manager-repeat.png)
- [第二次启动完整设备跟踪](evidence/guest-v30/startup.jsonl)
- [请求统计](evidence/guest-v30/trace-summary.json)

首次成功进程 PID 1704；第二次 PID 2160。第二次 UIA 确认窗口标题 SolidCAM Manager，包含 CAM-零件、刀具系统、加工工艺、孔向导工艺。25 次记录到的设备 IOCTL 全部成功；其中 16 次块解码请求，包含 15 种不同输入。跟踪只观察调用，不替换返回值。

## 构建和设备

SYS、INF、CAT、ARM64 节点/探测工具均由 Mac 构建。SYS 与 EXE 的 PE machine 为 Aarch64。两份 SYS 相同，SHA256：

`3b59bedbfda7cc6b3a734d50aae061cc689a623f730509f0e3146c645d68bb28`

客体 DriverStore 两个服务的文件哈希与本机包相同。原始 Solidcam.exe SHA256：

`7374d34154a47f03f0d48fbed9d86511a88a208b2e6cddbf6bbb5f3ffeeae5a9`

| 节点 | 包/服务 | 测试结果 |
|---|---|---|
| ROOT\VIRKEYARM64\0000 | oem34.inf / aksusb | CM_PROB_NONE |
| USB\VID_0529&PID_0001\2&3B88D3F4&0&1 | oem34.inf / aksusb | CM_PROB_NONE |
| USB\HASP\3&12B1D3C7&0&SC00 | oem33.inf / akshasp | CM_PROB_NONE |

两包版本 0.1.0.30。CAT 的 osslsigncode 验证通过，Windows 在测试模式加载成功。`Win32_PnPSignedDriver.IsSigned` 报 False，不能据此声称生产签名认证通过。仅公钥导入测试客体，私钥留在 Mac。

证据：[设备](evidence/guest-v30/devices.txt)、[包版本](evidence/guest-v30/driver-packages.txt)、[文件哈希](evidence/guest-v30/loaded-file-hashes.txt)、[根 CAT 验签](evidence/guest-v30/catalog-root-verification.txt)、[HASP CAT 验签](evidence/guest-v30/catalog-hasp-verification.txt)、[SetupAPI](evidence/guest-v30/setupapi.dev.log)。

## 协议验证

远端 x64 机器 `lmsc-i714700k-sustech` 上的 MulttKey 与用户文件 SHA256 相同：`daf40cea4c6025dc636e274899a3f2624fd16a74523b3fa6da964bfadeb1e57b`。

1. 区分两个 HASP 实例后，确认 SC 实例初始发现响应成功；另一个实例返回状态 7。此前混用两者是启动无法前进的原因之一。
2. 结合镜像块变换反汇编与公开项目结构，实现与 SecTable、密码相关的动态解码。272 字节请求尾部第二个 8 字节区域保存中间结果，并非第二个独立密文块。
3. Mac 上回放三次独立 x64 启动，34 个解码请求、31 种不同输入逐字节匹配；包含算法实现后重新采集的一组对照。另有六个静态查询、发现、版本、参数拒绝测试。
4. 解析器验证有效样本、缺项、错误值类型、截断字段和不支持的 MC 类型。
5. 客体双路径测试验证旧路径、新路径同名覆盖、删除测试覆盖项后恢复旧路径，详见 [registry-overlay.txt](evidence/guest-v30/registry-overlay.txt)。

设备诊断注册表中的 `UnsupportedChallengeCount` 和 `LastChallenge*` 保留了先前版本及故意发送无效请求的历史值，不能当作 v30 成功启动的失败次数。第二次启动的完整 trace 中无失败 IOCTL。

## 实现边界

- 通过的是本次 SC 样本与 SolidCAM 2024 的启动授权。没有验证完整 CAM 零件创建、刀路计算、后处理、所有模块或长时间会话。
- 测试前已经安装 SolidWorks；本次没有把“CAD 主程序缺失”作为结果解释。
- 原始 `solidcame.exe` 启动器仍存在独立的 ARM64 仿真错误 `0xC0000017`。直接启动原始 `Solidcam.exe` 成功，不代表桌面启动器已经修好。
- 配套 ARM64 功能层实现所需 IOCTL；UdeCx vendor USB 请求仍不完整，不保证第三方驱动/客户端的完整 USB 协议兼容。
- `hasplms` 正在运行，但本次授权关键路径是应用直接访问 HASP 设备接口。Sentinel ACC 列表不作为本次 legacy SC 授权的验收证据。
- 只支持 SC Type=1；MC Type=10 未实现。包为短期本地测试签名。

## 测试环境恢复

已先正常关机，再恢复安装 CAD 组件后的快照 `{d09acfde-e1b5-4c73-9614-8301c7110f1b}`，虚拟机恢复运行。恢复后未发现 VirKeyArm64 当前设备或驱动绑定；已核对 SolidCAM Embedded CAD 2024 及 SolidCAM 2024 仍安装。此次测试启动的远端 SolidCAM、Frida 服务及本地 SSH 转发已关闭。

[恢复后核验](evidence/guest-v30/post-restore-check.txt)；[快照清单](evidence/guest-v30/snapshots-after-restore.json)。随后按用户要求进行了下面的常驻安装。

## 常驻安装与重启复核

在 Git 提交 `d6cc270` 后，关闭 Parallels 虚拟机的 Secure Boot，启用 Windows 测试签名，导入 `VirKeyArm64-Test.cer` 公钥和 SC 注册表样本，安装 HASP 与根/USB 两包。首次启动原始 `Solidcam.exe` 通过授权检查、确认默认设置后进入 SolidCAM Manager。

再次重启 Windows 后，`tools/guest-persistent-check.ps1` 逐项核对证书、测试签名、`VirKeyArm64\Dumps` 优先选择、三个无问题码设备、两个 DriverStore 中 SYS 的 SHA256、`0.1.0.30` 包版本和 CAD/SolidCAM 文件，全部通过。重启后原始 `Solidcam.exe` 再次打开 SolidCAM Manager。**当前虚拟机保留这套安装**，未执行第二次快照恢复。

[持久性检查输出](evidence/guest-installed/persistent-check.txt)、[重启后界面](evidence/guest-installed/SolidCAM-Manager-after-reboot.png)、[设备状态](evidence/guest-installed/devices.txt)、[驱动文件哈希](evidence/guest-installed/loaded-file-hashes.txt)、[SetupAPI 安装日志](evidence/guest-installed/setupapi.dev.log)。

本轮使用的测试证书有效期至 2026-10-29 22:25（北京时间）；它并非生产签名证书。到期后继续运行的签名验收尚未验证，届时需重新签名并重新安装。
