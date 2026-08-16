#!/bin/bash
#
# shottr-zh — Shottr 一键汉化安装脚本
#
# 用法:
#   ./install.sh [Shottr.app 路径]     # 默认 /Applications/Shottr.app
#
# 脚本可安全重复运行（幂等）：检测到已注入时会先恢复原始二进制再重新安装。
#
set -euo pipefail

# ===== 配置 =====
REPO_URL="${REPO_URL:-https://github.com/sdgsacmljh/shottr-zh.git}"
TESTED_VERSION="1.9.1"          # 已验证兼容的 Shottr 版本
BUNDLE_ID="cc.ffitch.shottr"
APP_PATH="${1:-/Applications/Shottr.app}"
BACKUP_DIR="${SHOTTR_ZH_BACKUP_DIR:-$HOME/.shottr-zh/backup}"

# ===== 输出工具 =====
info()  { printf '\033[1;34m[信息]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[完成]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[警告]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[错误]\033[0m %s\n' "$*"; exit 1; }

# ===== 0. curl | bash 模式：脚本不在仓库内时先克隆仓库 =====
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$WORK_DIR/src/shottr_zh.m" ]; then
  command -v git >/dev/null 2>&1 || error "需要 git，请先安装 Xcode 命令行工具: xcode-select --install"
  info "通过 curl 运行，正在克隆仓库…"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  git clone --depth 1 "$REPO_URL" "$TMP_DIR/shottr-zh" || error "克隆仓库失败，请检查网络或 REPO_URL"
  WORK_DIR="$TMP_DIR/shottr-zh"
fi

# ===== 1. 依赖检查 =====
command -v clang     >/dev/null 2>&1 || error "未找到 clang，请先安装 Xcode 命令行工具: xcode-select --install"
command -v python3   >/dev/null 2>&1 || error "未找到 python3（macOS 10.15+ 自带）"
command -v codesign  >/dev/null 2>&1 || error "未找到 codesign"

# ===== 2. 检查 Shottr =====
[ -d "$APP_PATH" ] || error "未找到 Shottr: $APP_PATH（自定义路径用法: ./install.sh /path/to/Shottr.app）"
BIN="$APP_PATH/Contents/MacOS/Shottr"
[ -f "$BIN" ] || error "未找到 Shottr 主程序: $BIN"

VERSION="$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 未知)"
info "检测到 Shottr v$VERSION"
if [ "$VERSION" != "$TESTED_VERSION" ]; then
  warn "本项目仅在 v$TESTED_VERSION 上完整测试，v$VERSION 未经验证，如遇异常请运行 ./uninstall.sh 回退"
fi

# ===== 3. 幂等处理：已注入则先恢复原始二进制 =====
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/Shottr-$VERSION.bin"
if otool -L "$BIN" 2>/dev/null | grep -q shottr_zh; then
  info "检测到已安装汉化，先恢复原始二进制以保证安装干净…"
  [ -f "$BACKUP" ] || error "二进制已注入但备份 $BACKUP 不存在，请重新安装 Shottr 后再试"
  cp "$BACKUP" "$BIN"
elif [ -f "$BACKUP" ]; then
  info "发现既有备份，跳过重复备份"
else
  info "备份原始二进制 → $BACKUP"
  cp "$BIN" "$BACKUP"
fi

# ===== 4. 编译翻译动态库（双架构 + ARC，缺 -fobjc-arc 会导致悬垂指针崩溃）=====
info "编译翻译动态库（arm64 + x86_64）…"
mkdir -p "$WORK_DIR/build"
clang -fobjc-arc -dynamiclib -arch arm64 -arch x86_64 \
      -framework AppKit -framework UserNotifications \
      -o "$WORK_DIR/build/shottr_zh.dylib" \
      "$WORK_DIR/src/shottr_zh.m" || error "编译失败"

# ===== 5. 部署动态库与词典 =====
info "部署文件到 $APP_PATH …"
cp "$WORK_DIR/build/shottr_zh.dylib" "$APP_PATH/Contents/Frameworks/shottr_zh.dylib"
cp "$WORK_DIR/dict/zh_dict.plist"   "$APP_PATH/Contents/Resources/zh_dict.plist"

# ===== 6. 注入 LC_LOAD_DYLIB =====
info "注入加载命令到主二进制…"
python3 "$WORK_DIR/tools/inject_macho.py" "$BIN" \
        "@executable_path/../Frameworks/shottr_zh.dylib" || error "注入失败"

# ===== 7. 重新签名（ad-hoc）=====
info "重新签名…"
codesign --force --sign - "$APP_PATH/Contents/Frameworks/shottr_zh.dylib" >/dev/null 2>&1
codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || error "签名失败"
codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1 || warn "签名校验未通过，应用可能无法启动，请截图反馈"

# ===== 8. 重置屏幕录制授权（重签名后旧授权必然失效，必须重建）=====
info "重置屏幕录制授权（重签名后需要重新授权一次）…"
tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || warn "tccutil 执行失败，若截图提示无权限请手动重置"

# ===== 9. 重启 Shottr =====
killall Shottr >/dev/null 2>&1 || true
sleep 1
open "$APP_PATH"

ok "汉化安装完成！词典共 $(python3 -c "import plistlib;print(len(plistlib.load(open('$APP_PATH/Contents/Resources/zh_dict.plist','rb'))['exact']))") 条"
echo ""
echo "  ⚠️  重要：因为重新签名，首次截图时 macOS 会要求重新授予屏幕录制权限："
echo "     1. 使用一次截图功能，弹出提示时点击「打开系统设置」"
echo "     2. 在 隐私与安全性 → 屏幕与系统音频录制 中开启 Shottr"
echo "     3. 按提示退出并重新打开 Shottr"
echo ""
echo "  卸载汉化: ./uninstall.sh"
