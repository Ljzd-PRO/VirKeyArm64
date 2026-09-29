# VirKeyArm64 1.0.0

首次整理发布的 Windows 11 ARM64 SC `Type=1` 虚拟 USB／HASP 测试驱动包。两份 INF 的 `DriverVer` 为 `09/30/2026,1.0.0.0`。

## 内容

- ARM64 `VirKeyArm64.sys`，供根／USB 与 HASP 两份驱动包使用；SHA256：`3b59bedbfda7cc6b3a734d50aae061cc689a623f730509f0e3146c645d68bb28`。
- 对应 INF、重新生成并签署的 CAT、ARM64 `VirKeyNode.exe`、测试证书公钥和本次 SC 测试转储。
- 在客体中启用测试签名及安装／探测的 PowerShell 脚本、README、MIT License、逐文件 `SHA256SUMS.txt`。

**压缩包 SHA256：`848b552abf6a448bd43a7a866fd23a09dff1765aa88c8333bc0a02943bc604f0`**

## 验证范围

macOS 上的转储解析与协议回放测试通过；CAT 签名通过 `osslsigncode` 验证，两份 SYS 均为 ARM64 PE，二进制与此前在 Parallels Windows 11 ARM64 中通过 SolidCAM 2024 启动授权的 `0.1.0.30` 版逐字节相同。两份 SYS 的 CAT 成员验证通过。1.0.0 更新了 INF、CAT 和测试证书，**新包尚未在客体重新安装验证**。完整历史客体证据见仓库 `TEST-REPORT.md`。

此包仅供测试模式使用，尚不支持 MC `Type=10`、任意 Sentinel 锁或完整 USB vendor 请求。SolidCAM Embedded 的 `solidcame.exe` LAA 问题属于独立兼容性问题；压缩包不含该程序或改版文件。

随包测试签名证书有效至 **2027-09-30 04:52（北京时间）**，没有时间戳。测试私钥不在仓库或压缩包中。SC 转储含设备／许可相关数据；本 Release 位于私有仓库，请谨慎分享压缩包及其中的 `.reg`。

安装步骤、支持范围和恢复资料见 [README.md](README.md)。
