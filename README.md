# VirKeyArm64

**VirKeyArm64** 是面向 Windows 11 ARM64 的实验性虚拟 USB／HASP 内核驱动。它在 Windows ARM64 中呈现一个与特定 Sentinel SC 锁相符的设备，处理已观察到的 SC 请求，让依赖该锁的旧版 x64 应用能够在 Windows 用户态仿真环境中完成启动授权。驱动、INF、CAT 和辅助程序在 macOS 上构建；Windows 客体用于安装和验证。

从旧驱动不兼容、协议对照、Mac 构建和客体验收到启动器修复与发布的完整过程，见 [2026-09-30 调查、实现与验收全记录](docs/2026-09-30-investigation-and-results.md)。该记录逐项标明依据、已验证结果和仍未验证的范围。

当前发布版本为 **1.0.0**，只支持 **SC `Type=1`** 转储。此前 `0.1.0.30` 已在 Parallels Windows 11 ARM64 中用一份 SC 样本验证 SolidCAM 2024 的启动授权和 SolidCAM Manager。1.0.0 的两份 SYS 与那次客体验证的 SYS **逐字节相同**（SHA256 `3b59bedbfda7cc6b3a734d50aae061cc689a623f730509f0e3146c645d68bb28`）；1.0.0 更新了 INF 包版本、CAT 和一年期测试证书。**1.0.0 包尚未在客体单独重新安装验证。**

> 这是本地测试签名包，需要 Windows 测试签名模式以及信任随包提供的公钥证书。它没有微软生产签名，也不代表已支持任意 Sentinel 锁、USB 客户端或 SolidCAM 配置。转储含有设备与许可相关数据，请自行控制其保存和分享范围。

## 项目解决什么问题

旧版 `MulttKey.sys` 是 x64 内核驱动，Windows ARM64 无法直接加载它。Windows ARM64 可以仿真 x64 **用户态**程序，但其内核设备栈需要 ARM64 驱动。VirKeyArm64 在 ARM64 内核中实现所需的虚拟设备栈，并读取兼容格式的 SC 转储，让现有 x64 客户端继续由 Windows 用户态仿真运行。

本项目聚焦 **SC 锁的本地识别与启动授权**。SolidCAM 自带的 `solidcame.exe` 在测试虚拟机中还有独立的 `0xC0000017` 启动问题：该 x64 启动器未开启 LAA，导致 ARM64 仿真运行时无法预留所需虚拟地址空间。驱动不修改应用。启动器的诊断与用户侧 LAA 调整见 [LAUNCHER-ANALYSIS.md](LAUNCHER-ANALYSIS.md)；发布包不含 SolidCAM 文件或改版启动器。

## 设备与数据流

```text
注册表：MulttKey\Dumps 或 VirKeyArm64\Dumps
                │
                ▼
ROOT\VirKeyArm64 — ARM64 KMDF + UdeCx 控制器
                │
                ▼
USB\VID_0529&PID_0001 — 虚拟 USB 子设备
                │
                ▼
USB\HASP — ARM64 功能层和客户端设备接口
                │
                ▼
Windows 仿真中的 x64 SolidCAM 用户态程序
```

两份 INF 绑定同一份 `VirKeyArm64.sys`：根控制器和 USB 子设备使用 `aksusb` 服务，HASP 子设备使用 `akshasp` 服务。驱动复现对照机上观察到的发现、版本、序列号、数据、全局控制及动态块解码请求。兼容服务名不表示已实现原厂驱动的全部行为。

启动时读取以下路径的转储子项：

```text
HKLM\SYSTEM\CurrentControlSet\MulttKey\Dumps
HKLM\SYSTEM\CurrentControlSet\VirKeyArm64\Dumps
```

同名子项以 `VirKeyArm64` 路径为准。新路径的同名项即使格式无效，也不会悄悄退回旧路径的同名项。解析器检查注册表值类型和字段长度，只接受有效的 SC `Type=1`；若有多个有效项，按子项名称排序选择第一个。修改转储后需重启根设备，驱动不会实时监视注册表。

## 支持范围

| 项目 | 1.0.0 的范围 |
| --- | --- |
| 客体系统 | Windows 11 ARM64；INF 指定 build 26100 或更新版本 |
| 驱动框架 | KMDF 1.33、UdeCx 1.1 |
| 转储 | SC `Type=1`，字段类型与长度须符合解析器要求 |
| 应用验证 | SolidCAM 2024 启动授权与 SolidCAM Manager；未覆盖完整加工流程 |
| USB 行为 | 已观察到的功能层 IOCTL；UdeCx vendor control 请求未完整实现 |
| 尚不支持 | MC `Type=10`、任意 HASP 锁和任意 USB 客户端 |

测试设备树中的 `VID_0529&PID_0001&Rev_0321` 来自对照机。设备枚举成功只证明设备层工作，不能单独证明应用授权或 CAD/CAM 功能成功。

## 取得发布包

私有仓库的 [v1.0.0 Release](https://github.com/Ljzd-PRO/VirKeyArm64/releases/tag/v1.0.0) 提供 `VirKeyArm64-1.0.0-windows-arm64.zip`：

```text
VirKeyArm64-1.0.0/
├── README.md、LICENSE
├── package/
│   ├── VirKeyArm64.sys、VirKeyArm64.inf、VirKeyArm64.cat
│   ├── VirKeyNode.exe、VirKeyArm64-Test.cer
│   ├── VirKeyArm64-SC-Test.reg
│   └── hasp/VirKeyArm64.sys、VirKeyArm64.inf、VirKeyArm64.cat
└── tools/
    ├── guest-enable-test-package.ps1
    └── guest-install-and-probe.ps1
```

`.reg` 是本次 SC 测试数据，不是通用锁；也可以使用自己的兼容 SC 转储。压缩包不含测试签名**私钥**、微软 WDK 下载缓存、诊断日志或任何 SolidCAM／SolidWorks 安装文件。CAT 与随包证书配套；该证书有效至 **2027-09-30 04:52（北京时间）**，签名没有时间戳。过期后需重新构建、签名并更新测试客体中的证书。

## 在 Windows ARM64 测试客体中安装

安装需要管理员权限，会修改测试客体的启动配置和驱动。先保存虚拟机快照并检查 BitLocker 状态。测试签名模式通常需要关闭 Secure Boot；如使用 BitLocker，先准备恢复密钥。Parallels 的 Secure Boot 选项须在关机后更改。

解压后，在管理员 PowerShell 中将 `$release` 改为实际目录：

```powershell
$release = 'C:\Path\To\VirKeyArm64-1.0.0'
& "$release\tools\guest-enable-test-package.ps1"
```

脚本将随包的**公钥**导入 `LocalMachine\Root` 和 `TrustedPublisher`，并启用 `testsigning`。首次启用后重启 Windows，再导入与 SC 设备相符的转储。若使用私有发布包附带的本次样本：

```powershell
reg.exe import "$release\package\VirKeyArm64-SC-Test.reg"
& "$release\tools\guest-install-and-probe.ps1"
```

也可导入自己的 `.reg`，但须使用上述两个受支持路径之一，并满足 SC 字段要求。安装脚本把驱动复制到 `C:\Temp\VirKeyArm64`，先安装 HASP 子包，再创建 `ROOT\VirKeyArm64` 并安装根／USB 包；随后重启根设备并执行 `VirKeyNode.exe probe`。若提示需要重启，重启 Windows 后再次运行脚本。

探测通过后，再用目标应用检查授权。对本次 SolidCAM 测试，直接启动原始 `Solidcam.exe` 打开 Manager 是已验证的驱动路径；完整 Embedded CAD 入口还需要单独处理 `solidcame.exe` 的 LAA 问题。直接启动底层 `sldworks.exe` 不等价于完成 SolidCAM 启动器初始化。

## 验证与排错

在管理员 PowerShell 中检查设备和接口：

```powershell
Get-PnpDevice | Where-Object {
    $_.InstanceId -like 'ROOT\VIRKEYARM64*' -or
    $_.InstanceId -like 'USB\VID_0529&PID_0001*' -or
    $_.InstanceId -like 'USB\HASP*'
} | Format-Table FriendlyName,InstanceId,Status,Problem -AutoSize
& "$release\package\VirKeyNode.exe" probe
```

若驱动不能加载，记录设备问题码及 `C:\Windows\INF\setupapi.dev.log`，核对 ARM64 架构、CAT／证书匹配、测试签名和 Secure Boot 状态。设备正常但应用未识别时，需要记录客户端实际访问的接口与请求；本实现只覆盖已观察到的协议。应用启动器的 `0xC0000017` 应按独立问题诊断。

[TEST-REPORT.md](TEST-REPORT.md) 保存了 `0.1.0.30` 的客体请求跟踪、持久性检查和限制。1.0.0 SYS 与该报告的 SYS 哈希相同，但新的 INF、CAT 和证书尚无独立客体安装报告。

## 在 macOS 从源码构建

准备 macOS Clang、Rust 工具链、OpenSSL、`osslsigncode` 和访问固定版本微软 SDK/WDK NuGet 包的网络。首次检出后运行：

```sh
python3 tools/bootstrap-mac.py
python3 tests/test_sc_dump.py
python3 tests/test_protocol.py
zsh build.sh
osslsigncode verify -in package/VirKeyArm64.cat -CAfile build/test-cert.pem
osslsigncode verify -in package/hasp/VirKeyArm64.cat -CAfile build/test-cert.pem
```

`bootstrap-mac.py` 校验固定版本 WDK/SDK 下载包的 SHA256，配置 `rust-lld`，生成本机测试证书。依赖缓存、链接器路径和 `build/private/test-key.pem` 均在 Git 忽略目录内。重新链接会改变 PE 时间戳和校验和，需重新生成 CAT；新的包应在 ARM64 客体重新安装验证。Windows 不参与 SYS、INF、CAT 或辅助 EXE 的编译。

主要代码：`src/driver.c` 实现设备层；`src/registry.c` 选择转储；`src/sc_dump.c` 校验字段；`src/protocol.c` 和 `src/sc_cipher.c` 处理已观察到的请求与块变换。`tests/` 在 Mac 上验证解析器边界并回放请求。`tools/` 还保留研究与本机诊断脚本，发布包只收录安装所需的两个 PowerShell 脚本。

## 来源与许可

实现参考了旧 vusbbus 的设备结构、[UsbHasp](https://github.com/sam88651/UsbHasp) 的协议线索、用户提供的旧 x64 驱动镜像以及独立采集的 I/O。当前 C 驱动重新编写，没有直接复制旧 GPLv3 源文件；本项目不声称经过正式隔离的洁净室流程。设备标识、协议和兼容服务名用于互操作，不表示原厂认可。

本项目自行编写的源码与脚本按 [MIT License](LICENSE) 发布。微软 SDK/WDK、第三方产品、用户的转储数据及测试机器上的应用不因本仓库的 MIT 许可证而获得新的许可。使用者应自行确认其对相关设备、软件和转储数据的使用权。
