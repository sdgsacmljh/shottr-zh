# shottr-zh — Shottr 中文汉化补丁

一键将 [Shottr](https://shottr.cc)（macOS 截图工具）的**全部界面**汉化为中文，包括：

- 菜单栏下拉菜单
- 偏好设置窗口（通用 / 快捷键 / 上传 / 高级 / 许可证，含所有二级选项）
- 截图编辑器工具栏与提示文案
- 系统通知与各类弹窗

| 项目 | 说明 |
|---|---|
| 支持版本 | Shottr **v1.9.1**（build 128），其他版本未验证 |
| 系统要求 | macOS 13+（arm64 / x86_64），Xcode 命令行工具 |
| 安全性 | 本地编译、可一键完整卸载、原始二进制备份在 `~/.shottr-zh/backup` |
| 词典规模 | 466 条精确匹配 + 11 条前缀规则，可持续扩充 |

## 一键安装

```bash
git clone https://github.com/sdgsacmljh/shottr-zh.git
cd shottr-zh
./install.sh
```

或免克隆直接安装（发布后可用）：

```bash
curl -fsSL https://raw.githubusercontent.com/sdgsacmljh/shottr-zh/main/install.sh | bash
```

> Shottr 不在 `/Applications` 时，传入路径：`./install.sh /path/to/Shottr.app`

**安装后必看**：由于重新签名，macOS 会要求重新授予一次屏幕录制权限（这是重签名的必然结果，无法绕过）：

1. 用一次截图功能，弹出提示时点「打开系统设置」
2. 在 隐私与安全性 → 屏幕与系统音频录制 中开启 Shottr
3. 按提示退出并重新打开 Shottr

## 一键卸载

```bash
./uninstall.sh
```

恢复原始英文版（还原未修改的官方二进制，原始开发者签名自动生效）。

## 工作原理

Shottr 的界面字符串几乎全部由代码生成（非标准 Localizable.strings），传统 `.strings` 本地化方案行不通。本项目采用**运行时翻译**：

```
install.sh
  ├─ 1. 备份官方原始二进制 → ~/.shottr-zh/backup/Shottr-<版本>.bin
  ├─ 2. 现场编译翻译动态库 shottr_zh.dylib（arm64 + x86_64）
  ├─ 3. 部署 dylib 与词典 zh_dict.plist 到 app 内
  ├─ 4. 向主二进制注入 LC_LOAD_DYLIB（覆写 load commands 后的填充区，
  │     不移动任何数据，不改变文件大小）
  └─ 5. ad-hoc 重签名 + 重置屏幕录制授权
```

动态库通过 Objective-C method swizzle 拦截 AppKit 的文本设置入口：

- `NSMenuItem / NSMenu / NSButton / NSTextField / NSBox / NSTabViewItem / NSPopUpButton / NSSegmentedControl / NSWindow` 的标题与标签 setter
- `UNMutableNotificationContent` 的通知标题与正文
- **视图树遍历兜底**：窗口显示后延迟遍历整个 view 层级，翻译 nib 直接解码、不经 setter 的文本（设置窗口大量标签属于此类）
- 未命中的字符串自动记录到 `~/Library/Logs/shottr_zh.log`，便于持续补充词典

## 更新词典（参与贡献）

发现漏翻译的英文？两步即可：

1. 查看 `~/Library/Logs/shottr_zh.log`，把英文原文与中文翻译加入 `tools/gen_dict.py` 的 `EXACT` 字典
2. 生成并提交：

```bash
python3 tools/gen_dict.py   # 重新生成 dict/zh_dict.plist
./install.sh                # 重装（幂等，可安全重复运行）
```

欢迎通过 Pull Request 补充词条、适配新版本。

## 常见问题

**Q: 安装后截图提示需要权限，但设置里已经开了？**
重签名后系统视为"新应用"，旧授权记录绑定原开发者证书，永远无法匹配。运行安装时脚本已自动执行 `tccutil reset ScreenCapture cc.ffitch.shottr`，只需按弹窗重新授权一次。手动执行：`tccutil reset ScreenCapture cc.ffitch.shottr`

**Q: Shottr 应用内自更新后汉化消失了？**
更新会替换整个 app。重新运行 `./install.sh` 即可（备份按版本号区分，新版本会生成新备份）。

**Q: 安装后应用打不开 / 闪退？**
运行 `./uninstall.sh` 恢复，然后提交 issue 附上 `~/Library/Logs/DiagnosticReports/` 下最新的 Shottr 崩溃报告。

**Q: 会被系统 Gatekeeper 拦截吗？**
不会。修改的是本机已安装且已授权运行的应用，ad-hoc 重签名后可正常运行。

**Q: 翻译会改变截图内容或上传行为吗？**
不会。动态库只改 UI 文本，不碰任何功能逻辑、网络请求与文件。

## 免责声明

- 本项目修改第三方应用的二进制文件，**仅供个人学习研究使用**，使用风险自负
- Shottr 是 [Fogleman](https://github.com/fogleman) 的作品，Pro 功能请[购买正版](https://shottr.cc)支持作者
- 请勿将汉化后的应用再分发；本项目分发的只有汉化补丁本身（源码 + 词典 + 安装脚本）

## License

[MIT](LICENSE)（汉化补丁部分；Shottr 及其商标归原作者所有）
