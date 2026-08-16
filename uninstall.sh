#!/bin/bash
#
# shottr-zh — 卸载汉化，恢复 Shottr 原始状态
#
# 用法:
#   ./uninstall.sh [Shottr.app 路径]   # 默认 /Applications/Shottr.app
#
set -euo pipefail

BUNDLE_ID="cc.ffitch.shottr"
APP_PATH="${1:-/Applications/Shottr.app}"
BACKUP_DIR="${SHOTTR_ZH_BACKUP_DIR:-$HOME/.shottr-zh/backup}"

info()  { printf '\033[1;34m[信息]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[完成]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[警告]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[错误]\033[0m %s\n' "$*"; exit 1; }

[ -d "$APP_PATH" ] || error "未找到 Shottr: $APP_PATH"
BIN="$APP_PATH/Contents/MacOS/Shottr"

if ! otool -L "$BIN" 2>/dev/null | grep -q shottr_zh; then
  warn "未检测到汉化注入，无需卸载"
  exit 0
fi

# ===== 1. 恢复原始二进制 =====
BACKUP="$(ls -t "$BACKUP_DIR"/Shottr-*.bin 2>/dev/null | head -1 || true)"
[ -n "$BACKUP" ] || error "找不到原始备份（$BACKUP_DIR/Shottr-*.bin），无法恢复。请重新下载安装 Shottr"
info "恢复原始二进制: $(basename "$BACKUP")"
cp "$BACKUP" "$BIN"

# ===== 2. 清理注入的文件 =====
info "清理汉化文件…"
rm -f "$APP_PATH/Contents/Frameworks/shottr_zh.dylib"
rm -f "$APP_PATH/Contents/Resources/zh_dict.plist"

# ===== 3. 校验签名：原始二进制带原开发者签名，通常直接有效 =====
if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
  info "原始签名有效，无需重签"
else
  warn "原始签名校验未通过，使用 ad-hoc 签名修复…"
  codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || error "签名失败"
  # ad-hoc 重签后屏幕录制授权会失效，重置以便重新授予
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

# ===== 4. 重启 =====
killall Shottr >/dev/null 2>&1 || true
sleep 1
open "$APP_PATH"

ok "已恢复英文原版。备份保留在 $BACKUP_DIR（可手动删除整个目录）"
echo ""
echo "  提示：如果 Shottr 自带更新（应用内更新会替换整个 app），"
echo "  汉化会被覆盖，重新运行 ./install.sh 即可（备份按版本区分，互不影响）。"
