#!/bin/bash
# shottr-zh — 一键卸载并恢复完整官方 Shottr
set -euo pipefail

SUPPORTED_VERSION="1.9.1"
SUPPORTED_BUILD="128"
BUNDLE_ID="cc.ffitch.shottr"
SHOTTR_TEAM_ID="2Y683PRQWN"
APP_PATH="${1:-/Applications/Shottr.app}"
BACKUP_DIR="${SHOTTR_ZH_BACKUP_DIR:-$HOME/.shottr-zh/backups}"
SKIP_TCC="${SHOTTR_ZH_SKIP_TCC:-0}"
SKIP_LAUNCH="${SHOTTR_ZH_SKIP_LAUNCH:-0}"
SKIP_PROCESS_CONTROL="${SHOTTR_ZH_SKIP_PROCESS_CONTROL:-0}"

info()  { printf '\033[1;34m[信息]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[完成]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[警告]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }

validate_official_app() {
  target="$1"
  [ -d "$target" ] || error "完整官方备份不存在: $target"
  codesign --verify --deep --strict "$target" >/dev/null 2>&1 || error "官方备份签名无效，拒绝恢复"
  signature_info="$(codesign -dv --verbose=4 "$target" 2>&1)"
  grep -Fq "Identifier=$BUNDLE_ID" <<<"$signature_info" || error "备份不是 Shottr"
  grep -Fq "TeamIdentifier=$SHOTTR_TEAM_ID" <<<"$signature_info" || error "备份开发者团队标识不匹配"
  spctl --assess --type execute "$target" >/dev/null 2>&1 || error "Gatekeeper 未认可官方备份"
}

[ -d "$APP_PATH" ] || error "未找到 Shottr: $APP_PATH"
[ -w "$APP_PATH/Contents" ] || error "没有权限修改 $APP_PATH"
BIN="$APP_PATH/Contents/MacOS/Shottr"
MARKER="$APP_PATH/Contents/Resources/shottr_zh_backup_id"

CURRENT_LOADS="$(otool -L "$BIN" 2>/dev/null || true)"
if ! grep -Fq shottr_zh <<<"$CURRENT_LOADS"; then
  warn "未检测到汉化注入，无需卸载"
  exit 0
fi

[ -f "$MARKER" ] || \
  error "这是旧版汉化且没有完整备份标识。请从 https://shottr.cc 覆盖安装官方 Shottr"
BACKUP_ID="$(sed -n '1p' "$MARKER")"
case "$BACKUP_ID" in
  Shottr-${SUPPORTED_VERSION}-${SUPPORTED_BUILD}-*.app) ;;
  *) error "备份标识无效" ;;
esac
case "$BACKUP_ID" in
  *..*|*/*) error "备份标识包含非法路径" ;;
esac
BACKUP_APP="$BACKUP_DIR/$BACKUP_ID"
validate_official_app "$BACKUP_APP"

if [ "$SKIP_PROCESS_CONTROL" != "1" ]; then
  killall Shottr >/dev/null 2>&1 || true
  sleep 1
fi

info "从完整备份恢复官方 Shottr…"
ditto --rsrc --extattr "$BACKUP_APP" "$APP_PATH"
rm -f "$APP_PATH/Contents/Frameworks/shottr_zh.dylib"
rm -f "$APP_PATH/Contents/Resources/zh_dict.plist"
rm -f "$APP_PATH/Contents/Resources/shottr_zh_backup_id"
if [ ! -d "$BACKUP_APP/Contents/Frameworks" ]; then
  rmdir "$APP_PATH/Contents/Frameworks" >/dev/null 2>&1 || true
fi

codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1 || error "恢复后的官方签名校验失败"
signature_info="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
grep -Fq "TeamIdentifier=$SHOTTR_TEAM_ID" <<<"$signature_info" || error "未恢复官方 Developer ID 签名"
spctl --assess --type execute "$APP_PATH" >/dev/null 2>&1 || error "恢复后未通过 Gatekeeper"
xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true

if [ "$SKIP_TCC" != "1" ]; then
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
fi
if [ "$SKIP_LAUNCH" != "1" ]; then
  open "$APP_PATH" || error "官方 Shottr 启动失败"
fi

ok "已恢复官方英文版及 Developer ID 签名"
printf '完整备份保留在 %s，可供以后重新安装或恢复。\n' "${BACKUP_DIR}"
