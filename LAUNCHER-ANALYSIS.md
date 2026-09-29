# SolidCAM Embedded 2024 启动器 ARM64 诊断

日期：2026-09-30。环境：Parallels Windows 11 ARM64，build 26100.1742。

## 已确认的原因

原始安装快捷方式复现的错误是 **0xC0000017 / STATUS_NO_MEMORY**。`solidcame.exe` 是 x64 PE32+，COFF Characteristics 为 `0x0002`，未设置 `IMAGE_FILE_LARGE_ADDRESS_AWARE`。同套安装的 `Solidcam.exe` 为 `0x0022`，内置 `sldworks.exe` 为 `0x0023`，后二者均设置了 LAA。

微软明确说明：以 `/LARGEADDRESSAWARE:NO` 链接的 x64 程序可能无法在 ARM64 启动，因为仿真运行时需要保留 4 GB 虚拟地址空间，受限进程无法满足。这里的限制是虚拟地址空间，并非等同于物理 RAM 用尽。[微软 LAA 文档](https://learn.microsoft.com/en-us/cpp/build/reference/largeaddressaware-handle-large-addresses?view=msvc-170)。

本机对照实验支持这一原因：仅启用 LAA 的独立副本成功执行原启动流程并进入 SolidCAM Embedded 主窗口。无需依据本次错误推断 MFC、SolidCAM 主程序或内置 CAD 整体不支持 ARM64。此结论也不代表完整 CAD/CAM 功能均已验证。

## 对照结果

| 项目 | 原始安装入口 | 诊断副本 |
| --- | --- | --- |
| 文件 | `Solidcam\solidcame.exe` | 同目录 `solidcame-arm64-diagnostic.exe` |
| Characteristics | `0x0002` | `0x0022` |
| 修改 | 无 | 文件偏移 `0x11E`，`02` → `22`，仅一个字节 |
| 启动条件 | 已安装的 `SolidCAM2024E.lnk`，无参数，产品工作目录 | 相同工作目录，无参数 |
| 结果 | `0xC0000017` 对话框 | 启动内置 CAD、加载 HostLibSWEM、进入 SolidCAM 主窗口 |
| Authenticode | `Valid` | `HashMismatch`，修改 PE 头使原签名失效 |

原始 SHA256：`26d72b6c13a5704bf49097eb534d3b86f93f931870744b195373f2b54395dc7b`。

副本 SHA256：`86dd940519e96d5787282bcc38a56b8462d2f43602db80a9b554f31c97f4c726`。

这是 2026-09-30 初始诊断时的状态：原始文件及安装快捷方式当时未被覆盖。副本是兼容性诊断产物，不是厂商签名的发布版本；正式修复应由厂商启用 LAA 后重新签名。没有修改启动器的机器码、OEM 初始化逻辑、SolidCAM 主程序或 CAD 主程序。原有驱动包未改动。后续用户要求将 LAA 版设为原名默认入口，实际安装状态见文末。

启动时没有其他 CAD/CAM 进程。诊断启动返回 PID 8952；随后观察到：

```text
solidcame-arm64-diagnostic.exe (8952，完成启动后退出)
  └─ 内置 sldworks.exe (908)
       └─ Solidcam.exe (1460)
```

CAD 进程模块 `sldworks.exe`、`sldappu.dll` 文件版本均为 `32.1.0.0123`，并加载产品目录的 `HostLibSWEM.dll`。这是运行进程模块的文件版本证据，未冒称通过 Automation broker 读取了运行时 Revision API。短路径来自 Windows CIM 的实际输出。

- [原始错误截图](evidence/launcher-analysis/original-error.png)
- [Parallels 控制台成功界面](evidence/launcher-analysis/embedded-laa-console.png)
- [进程、模块版本、原始文件及副本哈希和签名状态](evidence/launcher-analysis/live-evidence.json)
- [安装快捷方式与文件清单](evidence/launcher-analysis/installed-entry.json)
- [单字节修改记录](evidence/launcher-analysis/patch.json)

Windows MCP 截图没有完整捕获右侧面板，Parallels 显示端截图可看到实际面板内容，因此使用控制台截图作为主视觉证据。未打开、保存或转换任何 CAD/CAM 项目，未验证刀路或长时间运行。

## 原启动器具体做什么

以原始镜像（ImageBase `0x400000`）的反汇编、导入表和字符串交叉引用分析，未获得厂商源码。以下地址为该版本静态虚拟地址：

1. `0x401AD7` 附近读取当前目录并构造嵌入式 CAD 路径。`0x403220` 辅助函数结合 `SOFTWARE\SolidCAM\SolidCAMCAD2024`、`SolidCAMCAD2024.Application` 的 CLSID 和 `LocalServer32` 定位已注册宿主。
2. `0x402850` 辅助函数读取产品 OEM 配置，包括 `SWOEMString`。报告不包含其具体内容。
3. `0x402103` 调用 `CreateProcessA` 启动目标 `sldworks.exe`，继承环境与工作目录。
4. `0x40213B` 构造 `SolidWorks_PID_%d`，结合 ROT/moniker 按新进程 PID 取得宿主接口。它不是无差别连接默认 `SldWorks.Application`。
5. `0x401ECE` 附近通过厂商接口传入选定 OEM 配置，继续初始化宿主；存在读取信息并写入临时 `seCopyRight.txt` 的路径。未恢复全部接口方法名，不将 vtable 偏移猜测为已确认 API。
6. 镜像还包含条件性的 `HostLibSWEM.dll` 注册路径和 AddIns 配置。不能据静态存在认定每次启动都会注册。

因此 `solidcame.exe` 确实是产品启动和初始化入口。直接启动底层 `sldworks.exe` 会省略启动器后续调用，不能仅凭界面类似认定二者完全等效。当前实验保留了原有流程，只修复阻止它执行的 PE 地址空间标志。

## 两个技能对替代入口的说明

已查阅 `solidcam-usage/references/host-identity-and-native-recovery.md`、`solidcam-automation/references/deployment-and-recovery.md`、`incident-antipatterns.md`。

- 安装的 Embedded 快捷方式目标为 `solidcame.exe`，参数为空，工作目录为产品 `Solidcam` 目录。
- `list_product_entries` / `launch_product` 保留安装入口的目标、参数、工作目录，仍调用 `solidcame.exe`。它们不提供另一种 Embedded 启动实现，并排除 raw `sldworks.exe` 和 For Operators。
- 本客体选择 Automation 主机时返回 `HOST_QUALIFICATION_FAILED`，说明该 Windows 用户尚未安装 broker。本次采用快捷方式只读清单、原生窗口与进程检查；没有为诊断部署 broker 或创建通用 SOLIDWORKS COM 宿主。
- 直接运行 `Solidcam.exe` 已在此前验证打开 Manager，但那项结果不等同于启动完整 Embedded CAD。

技能中的历史“future version”案例包含误连独立 SOLIDWORKS 2025 并保存文档，后来也有在已确认 2024 宿主中出现但原因未定的弹窗。它们不能证明本机直接启动内置 `sldworks.exe` 一定产生该错误。本次没有提供并打开可复现该错误的文件，不能声称 LAA 同时修复了文件版本问题。若出现该提示，需记录确切弹窗、宿主、输入文件及实际解析到的依赖版本。

## 复现与使用范围

Mac 上生成独立副本，脚本校验固定原始哈希、AMD64 PE 和头标志；拒绝覆盖已有目标。输出应与上方副本哈希一致。校验和字段保持原值，以隔离 LAA 这一变量。

```sh
python3 tools/make-launcher-laa-copy.py \
  build/guest-apps/solidcame.exe \
  build/launcher-study/solidcame-arm64-diagnostic.exe
```

客体已保留诊断副本于：

```text
C:\Program Files\SolidCAM2024\Solidcam\solidcame-arm64-diagnostic.exe
```

初始诊断时曾通过独立桌面入口 **SolidCAM2024E ARM64 (LAA)** 启动上述副本。后续用户要求改为原名默认入口，该临时桌面入口和诊断副本已经清理。启动工作目录仍为 `C:\Program Files\SolidCAM2024\Solidcam`，无额外参数。

脚本在 Mac 重新生成第二个副本，得到相同 SHA256，证明本次修改可重现。没有提交厂商 EXE、完整反汇编、进程环境或 OEM 配置内容。

## 后续安装：原名默认启用 LAA

按用户要求，已在同一 ARM64 客体将经哈希核验的 LAA 版放回 `C:\Program Files\SolidCAM2024\Solidcam\solidcame.exe`，把厂商原版完整备份为 `solidcame-no-laa-unmodified.exe`。原桌面和开始菜单 `SolidCAM2024E` 入口无需改目标，新建的 `SolidCAM2024E 无修改版` 入口指向备份。两套快捷方式均保留安装时的工作目录和空参数。同目录增加 `SOLIDCAME-LAA-README.md` 说明原因、差异、哈希和恢复方法。诊断副本及临时快捷方式在确认无人引用后清理。

[最终文件、LAA 位、签名与快捷方式核验](evidence/launcher-analysis/default-install-verification.json)。该核验确认原名文件的哈希为 `86dd940519e96d5787282bcc38a56b8462d2f43602db80a9b554f31c97f4c726`、Characteristics `0x0022`，备份哈希为 `26d72b6c13a5704bf49097eb534d3b86f93f931870744b195373f2b54395dc7b`、Characteristics `0x0002`。当前已有前次诊断启动的内置 CAD 会话，未结束用户会话来重复启动；启动成功的动态证据来自与现在原名文件**字节完全一致**的诊断副本。运行新原名快捷方式的独立复测尚未进行。
