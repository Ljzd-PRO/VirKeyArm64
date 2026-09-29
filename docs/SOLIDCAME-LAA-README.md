# SolidCAM 2024 Embedded 启动器：Windows ARM64 LAA 修改

此目录的 `solidcame.exe` 已由用户要求替换为启用 LAA 的版本，供 Parallels 中的 Windows 11 ARM64 使用。它仍是原来的 x64 SolidCAM Embedded 启动器，仅 PE 文件头的 `IMAGE_FILE_LARGE_ADDRESS_AWARE` 位发生变化。内置 CAD、SolidCAM 主程序和其他组件未因此修改。

| 文件 | 用途 | SHA256 |
| --- | --- | --- |
| `solidcame.exe` | 当前默认入口，启用 LAA | `86dd940519e96d5787282bcc38a56b8462d2f43602db80a9b554f31c97f4c726` |
| `solidcame-no-laa-unmodified.exe` | 安装时的原版备份，未启用 LAA | `26d72b6c13a5704bf49097eb534d3b86f93f931870744b195373f2b54395dc7b` |

原版在此 ARM64 客体启动即出现 `0xC0000017`。它是 x64 PE32+，COFF Characteristics 为 `0x0002`，未设置 LAA。微软说明，ARM64 的 x64 仿真运行时要预留约 4 GB 的虚拟地址空间；未开启 LAA 的 x64 程序只有受限的地址空间，可能无法启动。改版把 Characteristics 改为 `0x0022`；相对原版仅文件偏移 `0x11E` 的一个字节由 `02` 变为 `22`。此前以同字节内容的独立副本实测：启动器成功创建内置 `sldworks.exe`，加载 `HostLibSWEM.dll`，进入 SolidCAM Embedded 主窗口。

原名桌面和开始菜单快捷方式继续指向 `solidcame.exe`，即 LAA 版。新增的 **SolidCAM2024E 无修改版** 快捷方式指向 `solidcame-no-laa-unmodified.exe`，保留原产品工作目录和空参数，便于对照。它在当前 ARM64 客体仍预计报 `0xC0000017`。

修改 PE 头使改版失去厂商 Authenticode 签名一致性；原版备份仍保持原始签名。该改动只解决已证实的启动阶段地址空间问题，没有验证所有 CAM 项目、刀路或长期运行。升级或修复安装可能覆盖 `solidcame.exe`；出现新版文件时先比较架构、LAA 标志和哈希，切勿直接套用固定偏移。恢复原版可在退出相关程序后，从备份复制回 `solidcame.exe`。

更详细的反汇编、对照测试、截图和复现脚本位于本机工作区 `virkey-arm64/LAUNCHER-ANALYSIS.md`。微软说明：https://learn.microsoft.com/en-us/cpp/build/reference/largeaddressaware-handle-large-addresses
