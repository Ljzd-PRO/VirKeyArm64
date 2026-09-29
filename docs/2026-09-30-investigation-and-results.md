# 2026-09-30 调查、实现与验收全记录

这份记录面向接手项目的人，串联今天从旧驱动不兼容、协议对照、Mac 构建、ARM64 客体验证，到 SolidCAM Embedded 启动器诊断和 1.0.0 发布的全过程。详细原始记录分别保留在 [驱动测试报告](../TEST-REPORT.md)、[启动器分析](../LAUNCHER-ANALYSIS.md)、[发布记录](../RELEASE-1.0.0.md) 和 `evidence/`。本文的日期、测试结论均指 **2026-09-30（北京时间）**；Git 提交时间是提交时间，不一定是相应实验发生的准确时刻。

**本次整理只读取本地仓库中的源码、日志、截图、提交和已有报告；没有重新连接或操作远端 x64 Windows，也没有操作 Parallels Windows ARM64 虚拟机。** 下文所说的远端状态，均为此前采集时的状态，不是本次整理后的实时状态。

## 1. 起点、目标与范围

用户最初提供旧版 `MulttKey.inf`、`MulttKey.sys` 和三个注册表导出 `MC_SC_IM.reg`、`MC.reg`、`SC_IM.reg`。旧 INF 的平台模型只列 `NTx86`、`NTia64`、`NTamd64`，没有 `NTarm64`。在 ARM64 Windows 上尝试安装时曾得到设备问题码 `0x30`、问题状态 `0xC000036B`。这两个数值属于**旧驱动安装/加载阶段**；后文 `solidcame.exe` 的 `0xC0000017` 属于另一个**用户态启动阶段**问题，不能混为一谈。

仅给旧 INF 增加 `NTarm64` 节不会把 x64 内核映像变成 ARM64 映像。Windows ARM 的 x64 仿真作用于用户态程序，旧 `MulttKey.sys` 不能直接作为 ARM64 内核驱动加载；把原 SYS 包在一个 ARM64 驱动内也不能免除对原指令集、内核 ABI 和设备栈行为的重实现。讨论过把普通 U 盘改造成目标设备或让 macOS 虚拟 USB 经 Parallels 映射进客体，但它们仍须满足客体中的 USB 描述符、HASP 功能驱动、设备接口和授权请求契约。项目最终选择在客体中原生实现 **ARM64 虚拟 USB 控制器与功能层**，由 Mac 交叉编译，Windows 客体只负责安装和验收。

目标缩到用户已有的 **SC `Type=1`** 转储和 SolidCAM 2024 本地启动授权；`MC Type=10` 与任意其他 HASP 锁不在首版范围。授权是否通过，以应用实际进入 SolidCAM Manager 为准；设备管理器显示正常仅是中间条件。SolidWorks/CAD 宿主的可用性、SolidCAM Embedded 启动器以及完整 CAM 加工流程分别验证，避免把不同故障归给驱动。

## 2. 对照资料与可确认的契约

| 输入或方法 | 得到的事实 | 证据或限制 |
| --- | --- | --- |
| 旧 INF 和最初 ARM64 安装结果 | 原包无 `NTarm64` 模型，发生 `0x30` / `0xC000036B` | 用户提供的初始 INF 与安装反馈；这两项原始材料未原样纳入仓库 |
| 三份注册表导出 | 研究对象同时涉及 MC 和 SC；首版选 SC `Type=1`，兼容读取 `MulttKey\Dumps` 与新路径 | [解析器字段定义](../src/sc_dump.h)、[注册表读取实现](../src/registry.c)；完整个人转储内容不在本文复制 |
| 远端 x64 Windows 对照机 `lmsc-i714700k-sustech` | 已工作的 SC 子项名是 `4C8F743C`；虚拟设备报告 `USB\VID_0529&PID_0001&Rev_0321`；原栈为 `aksusb → MulttKey` | [驱动测试报告](../TEST-REPORT.md)；远端 `MulttKey.sys` 与用户样本的 SHA256 均为 `daf40cea4c6025dc636e274899a3f2624fd16a74523b3fa6da964bfadeb1e57b` |
| [旧 vusbbus 源码](https://github.com/flashermedia/vusbbus) 与 [UsbHasp](https://github.com/sam88651/UsbHasp) | 提供总线/锁模拟的结构及密码变换线索 | 旧 vusbbus 的注册表路径、设备修订号、字段长度与当前样本不同，只能作结构参考；其旧版代码没有直接复制进本项目 |
| 旧 SYS 静态分析、对照机 I/O 采集 | 识别设备接口、发现、版本、静态查询、块解码和会话响应；区分同时存在的 MC、SC 两个 HASP 实例 | [协议核心](../src/protocol.c)、[块变换](../src/sc_cipher.c)、[对照回放样本](../tests/fixtures/oracle-solidcam-holdout-v30.jsonl)；只覆盖启动期间实测的请求 |

对照中最重要的纠正是**区分两个 HASP 实例**。SC 实例的初始发现响应成功，另一实例返回状态 7；早期将二者的请求混在一起，会误判协议仍然失败。另一个纠正是 272 字节块解码请求末尾的第二个 8 字节区域保存中间结果，而不是第二个可独立解码的密文块。这些判断来自对照请求、旧 SYS 的相关逻辑和后来逐字节回放，并落实在 [协议实现](../src/protocol.c) 和 [测试](../tests/test_protocol.py)。

注册表读取结果是两条路径：

```text
HKLM\SYSTEM\CurrentControlSet\MulttKey\Dumps
HKLM\SYSTEM\CurrentControlSet\VirKeyArm64\Dumps
```

同名子项以新路径为准；新路径中存在但无效的同名项不会悄悄回退到旧路径。解析器检查注册表值类型及字段长度，跳过不支持的类型；多项有效 SC 转储时按子项名称选择。当前驱动在启动时读取，修改转储后需重启根设备。[实现](../src/registry.c) 和 [客体覆盖实验](../evidence/guest-v30/registry-overlay.txt)分别给出代码与行为证据；覆盖实验依次观察到旧路径、新路径覆盖、移除覆盖后恢复旧路径。

## 3. Mac 构建与驱动实现

驱动包是两份 INF、同一份 ARM64 SYS。根设备 `ROOT\VirKeyArm64` 由 KMDF + UdeCx 呈现一个 `VID_0529/PID_0001` USB 子设备；USB/HASP 功能层建立客户端所需的设备接口与已观察到的请求响应。INF 对 Windows 11 ARM64 build 26100 及以上声明 `NTarm64.10.0...26100`；服务名保留兼容性所需的 `aksusb` 和 `akshasp`，不表示实现了原厂驱动的完整功能。见 [根/USB INF](../package/VirKeyArm64.inf)、[HASP INF](../package/hasp/VirKeyArm64.inf)、[驱动设备层](../src/driver.c)。

Mac 构建采用本机 Clang 的 Windows ARM64 目标、`lld-link`、固定版本微软 SDK/WDK 头文件与库；`bootstrap-mac.py` 固定依赖包校验并准备本地测试证书。[构建脚本](../build.sh)保留了两项关键兼容处理：对 WDK 头文件中一处 ARM64 宏做本地单行修正，以及链接时使用 `/tsaware:no`。构建注释记录：`lld-link` 默认 TS-aware 标志曾使客体在执行 `DriverEntry` 之前返回 `STATUS_CONFLICTING_ADDRESSES`。CAT 在 Mac 从固定模板重建并用本机测试私钥签署；交付包仅包含公钥证书。[CAT 生成器](../tools/cat-from-template.py)和 [Mac 引导脚本](../tools/bootstrap-mac.py)保留具体过程。SYS、INF、CAT、ARM64 节点工具均在 Mac 生成，没有改用 Windows 编译。

解析器单测覆盖有效 SC、缺项、值类型错误、长度截断及不支持的 MC 类型；协议单测回放对照数据和错误参数。三次独立 x64 启动记录中的 **34 次块解码请求、31 种不同输入**与 Mac 侧实现逐字节匹配，另覆盖六项静态查询、发现、版本及参数拒绝场景。回放结果证明已记录输入的响应一致，不推导未观察到的全部 Sentinel/USB 行为。[转储测试](../tests/test_sc_dump.py)、[协议测试](../tests/test_protocol.py)和 [测试报告](../TEST-REPORT.md)保存范围与统计。

## 4. Windows ARM64 客体验收与状态变更

在已有 SolidWorks/CAD 组件的 Parallels Windows 11 ARM64 客体中，先检查 BitLocker 与启动配置、建立回退快照，再启用测试签名，安装测试证书**公钥**、SC 测试转储和两份驱动包。此前一轮实验结束后正常关机并恢复到安装 CAD 后的快照 `{d09acfde-e1b5-4c73-9614-8301c7110f1b}`；[恢复核验](../evidence/guest-v30/post-restore-check.txt)确认当时无 VirKeyArm64 绑定。此后按用户要求再次安装并保留，**没有第二次恢复快照**。因此该快照是安装前回退点，若将来恢复它会撤销随后保留的安装。[驱动测试报告](../TEST-REPORT.md)记录了这两个阶段，不能把最早的“已恢复”当作最终状态。

测试版 `0.1.0.30` 的三层节点均无 PnP 问题码：

| 节点 | 当时观察到的包/服务 | 结果 |
| --- | --- | --- |
| `ROOT\VIRKEYARM64\0000` | `oem34.inf` / `aksusb` | `CM_PROB_NONE` |
| `USB\VID_0529&PID_0001\2&3B88D3F4&0&1` | `oem34.inf` / `aksusb` | `CM_PROB_NONE` |
| `USB\HASP\3&12B1D3C7&0&SC00` | `oem33.inf` / `akshasp` | `CM_PROB_NONE` |

原始 `Solidcam.exe` 首次通过授权检查并进入设置/Manager；第二次启动直接进入 Manager。第二次的 [完整请求跟踪](../evidence/guest-v30/startup.jsonl)及 [统计](../evidence/guest-v30/trace-summary.json)显示 **25 次设备 IOCTL、无失败；其中 16 次动态块解码、15 种不同输入**。跟踪只观察调用，没有替换返回值。首次成功进程 PID 1704，第二次 PID 2160。窗口可见 CAM 零件、刀具系统、加工工艺、孔向导工艺等入口；[首次截图](../evidence/guest-v30/SolidCAM-Manager.png)、[第二次截图](../evidence/guest-v30/SolidCAM-Manager-repeat.png)是用户界面证据。这里的结论是**该 SC 样本的 SolidCAM 2024 启动授权通过**，不是所有 CAM 功能通过。

常驻安装后又重启客体。重启后的 [持久性检查](../evidence/guest-installed/persistent-check.txt)逐项确认测试签名、证书、从新注册表路径选用转储、三个无问题码设备、两个 DriverStore SYS 哈希、`0.1.0.30` 包版本及应用文件均存在；[重启后界面](../evidence/guest-installed/SolidCAM-Manager-after-reboot.png)再次证明 Manager 可打开。两处 SYS 的 SHA256 均为 `3b59bedbfda7cc6b3a734d50aae061cc689a623f730509f0e3146c645d68bb28`。[设备清单](../evidence/guest-installed/devices.txt)、[驱动文件哈希](../evidence/guest-installed/loaded-file-hashes.txt)和 [SetupAPI 日志](../evidence/guest-installed/setupapi.dev.log)可独立交叉核对。

`hasplms` 服务正在运行，但当次授权关键路径观察为应用直接访问 HASP 设备接口；Sentinel ACC 列表不能替代应用启动验收。诊断值 `UnsupportedChallengeCount` 与 `LastChallenge*` 曾包含早期版本及故意发送无效请求的历史记录，不能据此否定成功启动跟踪中“零失败 IOCTL”的事实。测试 CAT 验签及客体加载通过，只能说明**测试签名环境**可用；`Win32_PnPSignedDriver.IsSigned=False` 也不能解释成微软生产签名已经取得。最初客体安装的测试证书有效期至 **2026-10-29 22:25（北京时间）**；到期后的加载行为未验证。

## 5. 独立的 SolidCAM Embedded 启动器故障

驱动验收所用的是原始 `Solidcam.exe`，它能进入 Manager。安装的 Embedded 快捷方式却指向 `solidcame.exe`。该入口曾报 **`0xC0000017 / STATUS_NO_MEMORY`**，不能用驱动已枚举或 Manager 已打开来推断 Embedded 入口也正常。后来补装的 CAD 主程序已存在；直接运行内置 `sldworks.exe` 虽能显示 SolidCAM 风格界面，却绕过了启动器的宿主选择和 OEM 初始化，不能作为等效替代。[启动器专项报告](../LAUNCHER-ANALYSIS.md)记录原始窗口、静态分析和动态对照。

原始 `solidcame.exe` 是 x64 PE32+，COFF Characteristics `0x0002`，**缺少 `IMAGE_FILE_LARGE_ADDRESS_AWARE`**；原始 SHA256 为 `26d72b6c13a5704bf49097eb534d3b86f93f931870744b195373f2b54395dc7b`。微软 [LAA 文档](https://learn.microsoft.com/en-us/cpp/build/reference/largeaddressaware-handle-large-addresses?view=msvc-170)说明，禁用 LAA 的 x64 程序在 Windows ARM64 仿真下可能因运行时需预留 4 GB **虚拟地址空间**而无法启动。这与物理内存是否达到 4 GB 不是同一个条件，Parallels 增加客体 RAM 不能作为已证实的通用解法；也没有证据表明 Windows 有一个不改 EXE 即能替所有此类程序打开 LAA 的通用开关。

受控 A/B 测试仅把文件偏移 `0x11E` 的单字节 `02` 改成 `22`，令 Characteristics 成为 `0x0022`。副本 SHA256 `86dd940519e96d5787282bcc38a56b8462d2f43602db80a9b554f31c97f4c726`；[补丁记录](../evidence/launcher-analysis/patch.json)和 [生成脚本](../tools/make-launcher-laa-copy.py)能重现。原入口复现错误；相同工作目录、空参数的 LAA 副本成功启动内置 `sldworks.exe`，随后运行 `Solidcam.exe` 并加载 `HostLibSWEM.dll`，进入 Embedded 主窗口。[原错误截图](../evidence/launcher-analysis/original-error.png)、[成功界面](../evidence/launcher-analysis/embedded-laa-console.png)、[进程/模块/哈希记录](../evidence/launcher-analysis/live-evidence.json)形成因果对照。该实验强力支持 LAA 位是**这次启动失败**的原因，不证明完整 CAD/CAM 操作均可用。

对原版的静态反汇编显示，启动器结合 `SolidCAMCAD2024` 注册信息与 `SWOEMString` 定位并启动内置 `sldworks.exe`，按 `SolidWorks_PID_%d` 取得新进程的 ROT 宿主对象，再调用厂商接口初始化；还存在条件性的 `HostLibSWEM.dll` 注册路径。此为该版本镜像的静态行为，不把尚未恢复的方法名当作已确认 API。相关 `solidcam-usage` 和 `solidcam-automation` 技能的历史案例曾提到“高版本 SolidWorks”提示，但此次没有可复现的项目文件；本项目**未证明**该提示与 LAA 相同，或已被 LAA 改动解决。

按后续用户要求，客体中已将字节相同的 LAA 版放回产品目录原名 `solidcame.exe`，把原版备份为 `solidcame-no-laa-unmodified.exe`；桌面和开始菜单保留原名入口，另增“SolidCAM2024E 无修改版”入口，并在同目录加入 `SOLIDCAME-LAA-README.md`。最终 [文件、签名状态与四个快捷方式目标核验](../evidence/launcher-analysis/default-install-verification.json)显示：默认文件启用 LAA、原签名 `HashMismatch`；备份未启用 LAA、原签名 `Valid`。[部署说明源文件](SOLIDCAME-LAA-README.md)与客体文档同内容。**默认原名入口替换后未再独立启动复测**，因为当时已有上一步启动的 CAD 会话；其动态成功证据来自与默认文件字节完全一致的诊断副本。

## 6. 仓库、许可与 1.0.0 发布

当天建立了本项目 Git 仓库，并按实现、安装、诊断、默认入口、版本、README、LICENSE、发布分别提交。下表按本地 Git 的北京时间排序；细节可用 `git show <提交>` 核对。

| 提交 | 时间 | 记录内容 |
| --- | --- | --- |
| `d6cc270` | 04:02 | Mac 构建的 ARM64 SC 虚拟锁驱动、构建/测试/证据 |
| `d40d9d9` | 04:08 | 客体安装、重启后持久性验证 |
| `85d4833` | 04:30 | Embedded 启动器反汇编、LAA 诊断副本与对照 |
| `5c3769c` | 04:34 | LAA 副本的独立桌面入口 |
| `3589e53` | 04:50 | 将 LAA 版设为客体原名默认入口，备份原版及说明/快捷方式 |
| `6f01274` | 04:54 | 两份 INF 版本改为 `1.0.0.0` |
| `656093f` | 04:56 | 面向新访客的 [README](../README.md) |
| `2962460` | 04:57 | 单独加入 [MIT LICENSE](../LICENSE) |
| `e7237fd` | 04:58 | 1.0.0 发布说明、压缩包与校验 |

私有 [GitHub 仓库](https://github.com/Ljzd-PRO/VirKeyArm64)的简介为 “Windows 11 ARM64 virtual USB/HASP driver for SC Type=1 dumps, built on macOS”；topics 为 `kmdf`、`macos-build`、`sentinel-hasp`、`solidcam`、`udecx`、`virtual-usb`、`windows-arm64`、`windows-driver`。`v1.0.0` 标签指向 `e7237fd`；[Release](https://github.com/Ljzd-PRO/VirKeyArm64/releases/tag/v1.0.0)提供 `VirKeyArm64-1.0.0-windows-arm64.zip`，SHA256 为 `848b552abf6a448bd43a7a866fd23a09dff1765aa88c8333bc0a02943bc604f0`。此前发布操作已将 GitHub 上的压缩包重新下载、比较字节并通过 ZIP 完整性检查；这些是[发布记录](../RELEASE-1.0.0.md)记载的历史结果，本次整理未重新下载。

1.0.0 两份 INF 的 `DriverVer=09/30/2026,1.0.0.0`，重新生成了 CAT 和有效至 **2027-09-30 04:52（北京时间）** 的测试证书；SYS 与客体验证的 `0.1.0.30` **逐字节相同**。Mac 本地解析/协议测试、CAT 签名和 SYS 成员验证通过，**但新的 1.0.0 INF/CAT/证书组合尚未在 Windows 客体安装验收**。因此“0.1.0.30 在客体通过”和“1.0.0 发布包已独立客体通过”不是同一句话。ZIP 不含测试私钥、厂商 EXE 或诊断日志；其中 SC `.reg` 仍含设备/许可相关数据，发布仓库保持私有。[发布记录](../RELEASE-1.0.0.md)列出包内容与验证边界。

MIT 适用于项目自行编写的源码和脚本，不延伸至微软 SDK/WDK、厂商程序、第三方源码或用户转储。实现曾参考公开项目和原驱动行为，但没有直接复制旧 GPLv3 源文件；本项目也没有声称完成正式隔离的洁净室验证。

## 7. 结论、尚未证明的事项与交接提示

1. **已证明的核心结果：** Mac 构建的 `0.1.0.30` ARM64 驱动，在当时的 Windows 11 ARM64 客体上建立三层无故障设备，并使该 SC 样本的原始 `Solidcam.exe` 两次进入 Manager；常驻安装和重启后再次通过。证据是设备/哈希/SetupAPI 记录、完整请求跟踪和界面截图。
2. **已证明的独立结果：** 原版 `solidcame.exe` 报 `0xC0000017`，只增加 LAA 位的同内容副本成功进入 Embedded 主窗口；客体产品目录的默认文件与该成功副本哈希相同，原版有完整备份及独立快捷方式。默认原名入口替换后没有第三次独立启动记录。
3. **发布边界：** 1.0.0 ZIP、私有 Release 和 MIT 许可已经整理；1.0.0 的新 INF/CAT/证书组合尚无客体安装结果。历史客体所留为 `0.1.0.30`，不能称其已升级到 1.0.0。当前真实运行状态若将来要更新，须在再次获准操作客体后重新读取，不能仅从本报告推断。
4. **协议边界：** 只支持经校验的 SC `Type=1` 和启动阶段观察到的请求。设备修订号 `0321` 来自对照机，[设备描述符实现](../src/driver.c)中的其余字段仍属暂定值。MC `Type=10`、其他转储、完整 UdeCx vendor control 请求、其他 Sentinel 客户端及完整 CAM 零件/刀路/后处理均未验收。
5. **其他未证实点：** “高版本 SolidWorks”提示是否由具体宿主选择、文件版本或文档内容触发，未有本次可复现输入；LAA 改动不构成它的修复证据。测试签名不是微软生产签名；证书到期后的行为未测。客体原有快照是常驻安装之前的状态，恢复它会改变上述已记录环境。

后续代理可先从 [README](../README.md)理解安装和源码，再按 [驱动测试报告](../TEST-REPORT.md)、[启动器分析](../LAUNCHER-ANALYSIS.md)、[发布记录](../RELEASE-1.0.0.md)核对每项结论。本文为了可追溯而保留了哈希、设备 ID 和测试统计，未复制完整转储、授权请求载荷、测试私钥、厂商二进制或完整反汇编。今天这次文档整理遵守用户要求，**不对两台 Windows 系统进行任何操作**。
