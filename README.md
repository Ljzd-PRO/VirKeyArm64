# VirKeyArm64

Mac 构建的 Windows 11 ARM64 KMDF/UdeCx 研究驱动，首版支持本次 SC `Type=1` 样本。当前版本 **0.1.0.30**。

2026-09-30 已在 Parallels Windows 11 ARM64 中验证：原始 `Solidcam.exe` 通过启动授权检查，进入首次设置并打开 **SolidCAM Manager**；第二次启动复现成功。完整证据、限制和恢复记录见 [TEST-REPORT.md](TEST-REPORT.md)。这项结果不等同于完整 CAM 加工或所有 Sentinel 功能均可用。

## 已实现

- ARM64 UdeCx 控制器、`USB\VID_0529&PID_0001&Rev_0321` 子设备、ARM64 USB/HASP 功能层及观察到的设备接口。
- 同时读取 `HKLM\SYSTEM\CurrentControlSet\MulttKey\Dumps` 与 `HKLM\SYSTEM\CurrentControlSet\VirKeyArm64\Dumps`。同名子项以新路径优先；新项无效时也不会悄悄回退到旧同名项。
- 校验注册表值类型与字段长度，只选择一个有效 SC 实例；多个有效项按名称排序选择。重启根设备后重新读取。不支持 MC `Type=10`。
- 实现 SC 启动所需的发现、版本、数据、序列号、全局控制接口及动态块解码。不同挑战实时计算响应。
- 为兼容既有访问路径，两个功能服务名为 `aksusb`、`akshasp`，驱动二进制名称为 `VirKeyArm64.sys`。

## 在 Mac 构建与验证

所有 SYS、EXE、INF、CAT 均在 Mac 生成。首次从仓库检出时，运行 `python3 tools/bootstrap-mac.py`：它下载并校验固定版本的微软 ARM64 WDK/SDK 包，定位 Rust 工具链中的 `rust-lld`，生成本机测试证书。需要预先安装 macOS Clang、Rust、OpenSSL 和 `osslsigncode`。下载的第三方工具链、本机链接器路径及测试私钥不纳入 Git。`build.sh` 使用这些工具；Windows 不参与编译。

```sh
python3 tools/bootstrap-mac.py # 首次检出时运行
python3 tests/test_sc_dump.py
python3 tests/test_protocol.py
zsh build.sh
osslsigncode verify -in package/VirKeyArm64.cat -CAfile build/test-cert.pem
osslsigncode verify -in package/hasp/VirKeyArm64.cat -CAfile build/test-cert.pem
```

测试样本取自 `package/VirKeyArm64-SC-Test.reg`；对照回放位于 `tests/fixtures/`，测试不再依赖 Downloads 目录或临时跟踪文件。Mac 上的 dylib 测试编译同一份解析器和协议核心。

## 文件与安装

- `package/VirKeyArm64.{sys,inf,cat}`：根控制器与 USB 功能包。
- `package/hasp/VirKeyArm64.{sys,inf,cat}`：HASP 子设备功能包。
- `package/VirKeyNode.exe`：ARM64 根节点创建、移除与接口探测工具。
- `package/VirKeyArm64-Test.cer`：测试证书公钥。
- `package/VirKeyArm64-SC-Test.reg`：从用户提供文件提取的 SC 字段，写入新路径，不含原文件附带证书。

测试私钥位于 `build/private/test-key.pem`，不属于安装包，不复制进客体。CAT 为本地测试签名，不是微软生产签名。INF 目标为 Windows ARM64 build 26100 或更新版本，KMDF 1.33。

在已有快照且 BitLocker 状态已核对的测试客体中，先关闭虚拟机的 Secure Boot（Parallels 的 `prlctl set <VM-UUID> --efi-secure-boot off` 需要在关机后执行），再启动虚拟机，以管理员 PowerShell 执行以下流程。脚本从自身位置定位 `package/`，下方共享路径对应本机工作区。

```powershell
$project = '\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64'
& "$project\tools\guest-enable-test-package.ps1"
# 首次开启 testsigning 后，重启 Windows，再继续。
reg.exe import "$project\package\VirKeyArm64-SC-Test.reg"
& "$project\tools\guest-install-and-probe.ps1"
# 若返回 3010，重启 Windows 并重新运行安装脚本。
& 'C:\Program Files\SolidCAM2024\Solidcam\Solidcam.exe'
```

安装脚本可重复运行。根节点与子设备正常后，probe 应读出 SC 序列号 `4F2F4F2D`、首字 `0ECA`，并通过块解码探测。观察到的成功启动由应用直接打开 HASP 接口完成；`hasplms` 服务运行本身不能证明它代理了全部授权请求。

## 范围与参考

`src/sc_dump.c` 是便携解析器，`src/registry.c` 实现内核双路径选择，`src/protocol.c` 与 `src/sc_cipher.c` 实现观察到的 SC 协议，`src/driver.c` 提供设备层。

参考了旧 vusbbus 的结构、[UsbHasp](https://github.com/sam88651/UsbHasp) 的块变换结构、用户提供的 MulttKey x64 镜像反汇编及远端实际 I/O。当前 C 实现重新编写，没有将旧 GPLv3 源文件直接复制进驱动；本项目不声称经过正式隔离的洁净室流程。

UdeCx 的 USB vendor control 请求尚未完整实现；现阶段由配套功能层处理已观察到的 IOCTL。不要把本包视为任意 USB 客户端都可用的完整硬件仿真。此前启动授权验收使用原始 `Solidcam.exe`，未修改 SolidCAM 或 Sentinel 用户态二进制。后续已独立定位 `solidcame.exe` 的 `0xC0000017`：原始 x64 启动器缺少 LAA 标志。只启用该标志的独立诊断副本已在 ARM64 客体进入完整 Embedded 主窗口；原始文件及快捷方式保留。副本签名失效及完整证据见 [LAUNCHER-ANALYSIS.md](LAUNCHER-ANALYSIS.md)。

测试 VM 为 `decbd7d1-b22f-4c4e-95e7-fd95b44e8671`。2026-09-30 已在其中安装并重启验证：测试签名启用、两份驱动包与三个设备节点保留，原始 `Solidcam.exe` 再次打开 SolidCAM Manager。安装前恢复点是补装 CAD 组件后的 `{d09acfde-e1b5-4c73-9614-8301c7110f1b}`；恢复它会撤销本轮常驻安装。当前测试证书有效期至 **2026-10-29 22:25（北京时间）**，届时继续测试须重新签名并安装。
