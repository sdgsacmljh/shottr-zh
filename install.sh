#!/bin/bash
#
# shottr-zh — Shottr 一键汉化安装器
# 支持：Shottr 1.9.1 (build 128)，macOS 15+，Intel / Apple Silicon
#
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/sdgsacmljh/shottr-zh.git}"
SUPPORTED_VERSION="1.9.1"
SUPPORTED_BUILD="128"
MIN_MACOS_MAJOR=15
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

TMP_DIR=""
ROLLBACK_REQUIRED=0
BACKUP_APP=""
BACKUP_TMP=""

cleanup_and_rollback() {
  status=$?
  set +e
  if [ "$status" -ne 0 ] && [ "$ROLLBACK_REQUIRED" -eq 1 ] && [ -d "$BACKUP_APP" ]; then
    warn "安装未完成，正在自动恢复官方原版…"
    restore_app "$BACKUP_APP"
    if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
      ok "已自动回滚，Shottr 未被损坏"
    else
      warn "自动回滚后的签名校验失败，请从 https://shottr.cc 重新安装 Shottr"
    fi
  fi
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
  if [ -n "$BACKUP_TMP" ] && [ -e "$BACKUP_TMP" ]; then
    rm -rf "$BACKUP_TMP"
  fi
  exit "$status"
}
trap cleanup_and_rollback EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "$2"
}

plist_value() {
  plutil -extract "$1" raw -o - "$2" 2>/dev/null
}

validate_backup_id() {
  case "$1" in
    Shottr-${SUPPORTED_VERSION}-${SUPPORTED_BUILD}-*.app) ;;
    *) error "备份标识无效，请重新安装官方 Shottr 后再试" ;;
  esac
  case "$1" in
    *..*|*/*) error "备份标识包含非法路径" ;;
  esac
}

validate_official_app() {
  target="$1"
  [ -d "$target" ] || error "官方备份不存在: $target"
  codesign --verify --deep --strict "$target" >/dev/null 2>&1 || \
    error "Shottr 官方签名校验失败。请从 https://shottr.cc 重新下载，勿继续修改"
  signature_info="$(codesign -dv --verbose=4 "$target" 2>&1)"
  grep -Fq "Identifier=$BUNDLE_ID" <<<"$signature_info" || \
    error "应用标识不是官方 Shottr ($BUNDLE_ID)"
  grep -Fq "TeamIdentifier=$SHOTTR_TEAM_ID" <<<"$signature_info" || \
    error "开发者团队标识不匹配，拒绝修改非官方应用"
  spctl --assess --type execute "$target" >/dev/null 2>&1 || \
    error "Gatekeeper 未认可该 Shottr，请从 https://shottr.cc 重新下载"
}

restore_app() {
  backup="$1"
  ditto --rsrc --extattr "$backup" "$APP_PATH"
  rm -f "$APP_PATH/Contents/Frameworks/shottr_zh.dylib"
  rm -f "$APP_PATH/Contents/Resources/zh_dict.plist"
  rm -f "$APP_PATH/Contents/Resources/shottr_zh_backup_id"
  if [ ! -d "$backup/Contents/Frameworks" ]; then
    rmdir "$APP_PATH/Contents/Frameworks" >/dev/null 2>&1 || true
  fi
}

# curl | bash 模式下，先获取完整仓库。
SOURCE_DIR="$(dirname "${BASH_SOURCE[0]:-/dev/stdin}")"
if [ -d "$SOURCE_DIR" ]; then
  WORK_DIR="$(cd "$SOURCE_DIR" && pwd)"
else
  WORK_DIR="$(pwd)"
fi
if [ ! -f "$WORK_DIR/src/shottr_zh.m" ]; then
  require_command git "需要 Git/Xcode 命令行工具，请先运行: xcode-select --install"
  info "正在获取 shottr-zh…"
  TMP_DIR="$(mktemp -d)"
  git clone --depth 1 "$REPO_URL" "$TMP_DIR/shottr-zh" >/dev/null 2>&1 || \
    error "克隆仓库失败，请检查网络连接"
  WORK_DIR="$TMP_DIR/shottr-zh"
fi

for tool in clang python3 codesign otool lipo xattr ditto plutil spctl shasum; do
  require_command "$tool" "缺少 ${tool}，请先运行: xcode-select --install"
done

OS_VERSION="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VERSION%%.*}"
case "$OS_MAJOR" in
  ''|*[!0-9]*) error "无法识别 macOS 版本: $OS_VERSION" ;;
esac
[ "$OS_MAJOR" -ge "$MIN_MACOS_MAJOR" ] || \
  error "仅支持 macOS ${MIN_MACOS_MAJOR} 及以上，当前为 macOS $OS_VERSION"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  arm64|x86_64) ;;
  *) error "不支持的处理器架构: $HOST_ARCH" ;;
esac

[ -d "$APP_PATH" ] || error "未找到 Shottr: $APP_PATH"
[ -w "$APP_PATH/Contents" ] || error "没有权限修改 ${APP_PATH}；请将 Shottr 放入当前用户可写的 Applications 文件夹"
PLIST="$APP_PATH/Contents/Info.plist"
BIN="$APP_PATH/Contents/MacOS/Shottr"
[ -f "$PLIST" ] || error "应用缺少 Info.plist: $PLIST"
[ -f "$BIN" ] || error "应用缺少主程序: $BIN"

VERSION="$(plist_value CFBundleShortVersionString "$PLIST" || true)"
BUILD="$(plist_value CFBundleVersion "$PLIST" || true)"
info "检测到 Shottr v$VERSION (build ${BUILD})，macOS ${OS_VERSION}，$HOST_ARCH"
[ "$VERSION" = "$SUPPORTED_VERSION" ] && [ "$BUILD" = "$SUPPORTED_BUILD" ] || \
  error "仅支持 Shottr v$SUPPORTED_VERSION (build $SUPPORTED_BUILD)。为避免损坏，其他版本不会继续"

APP_ARCHS="$(lipo -archs "$BIN" 2>/dev/null || true)"
grep -Fwq arm64 <<<"$APP_ARCHS" || error "官方程序缺少 arm64 架构"
grep -Fwq x86_64 <<<"$APP_ARCHS" || error "官方程序缺少 x86_64 架构"

PATCH_MARKER="$APP_PATH/Contents/Resources/shottr_zh_backup_id"
mkdir -p "$BACKUP_DIR"

CURRENT_LOADS="$(otool -L "$BIN" 2>/dev/null || true)"
if grep -Fq shottr_zh <<<"$CURRENT_LOADS"; then
  [ -f "$PATCH_MARKER" ] || \
    error "检测到旧版汉化但没有完整应用备份标识。请先从 https://shottr.cc 覆盖安装官方 v${SUPPORTED_VERSION}，再运行本脚本"
  BACKUP_ID="$(sed -n '1p' "$PATCH_MARKER")"
  validate_backup_id "$BACKUP_ID"
  BACKUP_APP="$BACKUP_DIR/$BACKUP_ID"
  validate_official_app "$BACKUP_APP"
  info "检测到已安装汉化，先从完整备份恢复后重新安装…"
  restore_app "$BACKUP_APP"
  validate_official_app "$APP_PATH"
  BIN="$APP_PATH/Contents/MacOS/Shottr"
else
  validate_official_app "$APP_PATH"
  ORIGINAL_SHA="$(shasum -a 256 "$BIN" | awk '{print $1}')"
  BACKUP_ID="Shottr-${VERSION}-${BUILD}-${ORIGINAL_SHA}.app"
  validate_backup_id "$BACKUP_ID"
  BACKUP_APP="$BACKUP_DIR/$BACKUP_ID"
  if [ -d "$BACKUP_APP" ]; then
    validate_official_app "$BACKUP_APP"
    info "复用已验证的完整官方备份: $BACKUP_APP"
  else
    BACKUP_TMP="${BACKUP_APP%.app}.tmp.$$.app"
    [ ! -e "$BACKUP_TMP" ] || error "临时备份路径已存在: $BACKUP_TMP"
    info "完整备份官方 Shottr → $BACKUP_APP"
    ditto --rsrc --extattr "$APP_PATH" "$BACKUP_TMP"
    validate_official_app "$BACKUP_TMP"
    mv "$BACKUP_TMP" "$BACKUP_APP"
  fi
fi

if [ "$SKIP_PROCESS_CONTROL" != "1" ]; then
  killall Shottr >/dev/null 2>&1 || true
  sleep 1
fi

ROLLBACK_REQUIRED=1

info "编译汉化动态库（arm64 + x86_64，最低 macOS ${MIN_MACOS_MAJOR}.0）…"
mkdir -p "$WORK_DIR/build"
clang -fobjc-arc -dynamiclib -arch arm64 -arch x86_64 \
      -mmacosx-version-min="${MIN_MACOS_MAJOR}.0" \
      -framework AppKit -framework UserNotifications \
      -o "$WORK_DIR/build/shottr_zh.dylib" \
      "$WORK_DIR/src/shottr_zh.m" || error "动态库编译失败"

DYLIB="$APP_PATH/Contents/Frameworks/shottr_zh.dylib"
DICT="$APP_PATH/Contents/Resources/zh_dict.plist"
mkdir -p "$APP_PATH/Contents/Frameworks"
cp "$WORK_DIR/build/shottr_zh.dylib" "$DYLIB"
cp "$WORK_DIR/dict/zh_dict.plist" "$DICT"
printf '%s\n' "$BACKUP_ID" > "$PATCH_MARKER"

if [ "${SHOTTR_ZH_TEST_FAIL_AFTER_DEPLOY:-0}" = "1" ]; then
  error "测试故障点：部署后中止"
fi

info "向 Shottr 双架构主程序注入汉化库…"
python3 "$WORK_DIR/tools/inject_macho.py" "$BIN" \
        "@executable_path/../Frameworks/shottr_zh.dylib" || error "Mach-O 注入失败"

info "本地重新签名并验证…"
codesign --force --sign - "$DYLIB" >/dev/null 2>&1 || error "动态库签名失败"
codesign --force --sign - \
  --preserve-metadata=identifier,entitlements,flags,runtime \
  "$APP_PATH" >/dev/null 2>&1 || error "应用签名失败"
codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1 || error "应用签名校验失败"

DYLIB_ARCHS="$(lipo -archs "$DYLIB")"
grep -Fwq arm64 <<<"$DYLIB_ARCHS" || error "汉化库缺少 arm64 架构"
grep -Fwq x86_64 <<<"$DYLIB_ARCHS" || error "汉化库缺少 x86_64 架构"
LOAD_COUNT="$(otool -L "$BIN" | grep -Fc '@executable_path/../Frameworks/shottr_zh.dylib')"
[ "$LOAD_COUNT" -eq 2 ] || error "汉化库未同时注入两个架构"

# 用户已主动运行本地修改器，且修改前已验证官方 Team ID 与公证签名。
# ad-hoc 重签后的应用无法继续使用下载隔离票据，因此仅清除该应用的 quarantine 属性。
if xattr -p com.apple.quarantine "$APP_PATH" >/dev/null 2>&1; then
  info "清除已验证官方应用的下载隔离标记…"
  xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true
fi

if [ "$SKIP_TCC" != "1" ]; then
  info "重置屏幕录制授权（首次截图时需重新允许）…"
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || \
    warn "无法自动重置权限；如截图无权限，请手动执行: tccutil reset ScreenCapture $BUNDLE_ID"
fi

if [ "$SKIP_LAUNCH" != "1" ]; then
  open "$APP_PATH" || error "Shottr 启动失败，正在回滚"
fi

DICT_COUNT="$(python3 -c 'import plistlib,sys; print(len(plistlib.load(open(sys.argv[1], "rb"))["exact"]))' "$DICT")"
ROLLBACK_REQUIRED=0
ok "汉化安装完成：$DICT_COUNT 条词典，Intel / Apple Silicon 双架构"
printf '\n首次截图时，请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中重新允许 Shottr。\n'
printf '一键卸载：curl -fsSL https://raw.githubusercontent.com/sdgsacmljh/shottr-zh/main/uninstall.sh | bash\n'
