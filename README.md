# shottr-zh — Shottr 中文汉化补丁

[![Verify one-click installer](https://github.com/sdgsacmljh/shottr-zh/actions/workflows/verify.yml/badge.svg)](https://github.com/sdgsacmljh/shottr-zh/actions/workflows/verify.yml)

将 macOS 截图工具 [Shottr](https://shottr.cc) 的菜单、设置、编辑器工具栏、通知和弹窗汉化为简体中文。

## 明确支持范围

| 项目 | 支持范围 |
|---|---|
| Shottr | **v1.9.1，build 128**（[官方下载](https://shottr.cc/dl/Shottr-1.9.1.dmg)） |
| macOS | **macOS 15 及以上** |
| Mac | **Intel（x86_64）与 Apple Silicon（arm64）** |
| 安装位置 | 默认 `/Applications/Shottr.app`，也支持自定义路径 |

安装器会同时核对版本号、build、Bundle ID、官方 Developer Team ID、公证签名和双架构。任何一项不匹配都会在修改前停止，因此**不会尝试修改未验证的 Shottr 版本**。

GitHub Actions 每周从 Shottr 官方重新下载 DMG，并在 macOS 15/26、Intel/Apple Silicon runner 上验证：全新安装、重复安装、双架构注入、签名、完整卸载和官方签名恢复。

## 使用前准备

1. 安装官方 Shottr v1.9.1 build 128，并拖入“应用程序”文件夹。
2. 安装 Xcode 命令行工具（只需一次）：

```bash
xcode-select --install
```

命令行工具提供本地编译所需的 `clang`、`python3`、`codesign` 和 Mach-O 工具。汉化库只在你的 Mac 上编译，不下载预编译二进制。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/sdgsacmljh/shottr-zh/main/install.sh | bash
```

自定义 Shottr 路径：

```bash
curl -fsSL https://raw.githubusercontent.com/sdgsacmljh/shottr-zh/main/install.sh | bash -s -- "/path/to/Shottr.app"
```

安装器会自动完成：

1. 验证这是 Shottr 官方签名并通过 Apple Gatekeeper 的 v1.9.1 build 128。
2. 完整备份整个官方应用到 `~/.shottr-zh/backups`，包括 Developer ID 签名。
3. 本地编译 arm64 + x86_64 汉化动态库。
4. 创建缺失的 Frameworks 目录、部署词典并安全注入两个架构。
5. ad-hoc 重签、校验应用，并在验证官方来源后清除该应用的下载隔离标记。
6. 重置屏幕录制授权并启动 Shottr。
7. 任一步骤失败时自动恢复完整官方应用。

首次截图时，macOS 会要求重新授予屏幕录制权限：在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 Shottr，然后重新打开应用。

## 一键卸载

```bash
curl -fsSL https://raw.githubusercontent.com/sdgsacmljh/shottr-zh/main/uninstall.sh | bash
```

卸载器使用安装时记录的精确备份恢复整个官方应用，而不是只替换主二进制。完成后会验证：

- 汉化库和词典已删除；
- 官方 Developer ID Team ID 已恢复；
- Apple Gatekeeper 重新接受该应用；
- 原始主程序哈希与安装前一致。

## 从旧版 shottr-zh 迁移

2026-08-16 之前发布的版本只备份了 Shottr 主二进制，无法恢复整个官方签名。若已安装旧版汉化：

1. 从[官方 DMG](https://shottr.cc/dl/Shottr-1.9.1.dmg)将 Shottr 覆盖复制到“应用程序”；
2. 确认官方英文版可以启动；
3. 再运行上面的一键安装命令。

新版安装器检测到旧版注入但找不到完整应用备份时会安全退出，不会继续覆盖。

## 工作原理

Shottr 的界面字符串主要由代码生成，传统 `Localizable.strings` 无法覆盖。本项目在主程序的 Mach-O load-command 填充区写入 `LC_LOAD_DYLIB`，加载本地编译的翻译库。注入过程不会移动节区数据，也不会改变注入时的文件长度。

动态库通过 Objective-C method swizzle 翻译 AppKit 控件、菜单、窗口和通知文本，并遍历视图树处理 nib 直接解码的内容。当前词典包含 466 条精确匹配和 11 条前缀规则；未命中的文本记录到 `~/Library/Logs/shottr_zh.log`。

## 开发与验证

```bash
python3 tests/test_inject_macho.py -v
./tests/e2e_official_dmg.sh
```

端到端测试下载官方 DMG，只修改临时应用副本，不会碰 `/Applications/Shottr.app`，也不会重置本机权限。

补充翻译后重新生成词典：

```bash
python3 tools/gen_dict.py
```

## 常见问题

**为什么不支持其他 Shottr 版本？**

Mach-O 布局和界面字符串可能随版本变化。未经官方 DMG 端到端验证就自动注入存在损坏风险，因此安装器选择安全拒绝。适配新版本后会更新支持矩阵。

**为什么需要重新授权屏幕录制？**

主程序修改后必须本地重签，macOS 会把它视为新的代码身份。安装器会重置旧授权，用户需重新允许一次。

**Shottr 自动更新后汉化消失怎么办？**

更新会替换整个应用。只有当新版本已列入上方支持矩阵时才能重新安装；否则请等待项目适配。

## 免责声明

- 本项目修改第三方应用，仅供个人学习研究，使用风险自负。
- Shottr 及其商标属于原作者；Pro 功能请[购买正版](https://shottr.cc)。
- 请勿分发修改后的 Shottr 应用。本仓库只提供 MIT 许可的汉化源码、词典和安装工具。

## License

[MIT](LICENSE)（仅适用于本项目代码与词典）
