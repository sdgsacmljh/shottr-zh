#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOTTR_DMG_URL="https://shottr.cc/dl/Shottr-1.9.1.dmg"
TMP_ROOT="$(mktemp -d)"
MOUNT_POINT="$TMP_ROOT/mount"
APP_PATH="$TMP_ROOT/consumer install/Shottr Test.app"
BACKUP_DIR="$TMP_ROOT/backups"

cleanup() {
  set +e
  hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$MOUNT_POINT" "$(dirname "$APP_PATH")" "$BACKUP_DIR"
curl -fsSL "$SHOTTR_DMG_URL" -o "$TMP_ROOT/Shottr-1.9.1.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$TMP_ROOT/Shottr-1.9.1.dmg" >/dev/null

SOURCE_APP="$MOUNT_POINT/Shottr.app"
[ "$(plutil -extract CFBundleShortVersionString raw -o - "$SOURCE_APP/Contents/Info.plist")" = "1.9.1" ]
[ "$(plutil -extract CFBundleVersion raw -o - "$SOURCE_APP/Contents/Info.plist")" = "128" ]
codesign --verify --deep --strict "$SOURCE_APP"
spctl --assess --type execute "$SOURCE_APP"

ditto --rsrc --extattr "$SOURCE_APP" "$APP_PATH"
ORIGINAL_SHA="$(shasum -a 256 "$APP_PATH/Contents/MacOS/Shottr" | awk '{print $1}')"
xattr -w com.apple.quarantine '0081;00000000;Safari;00000000-0000-0000-0000-000000000000' "$APP_PATH"

run_installer() {
  SHOTTR_ZH_BACKUP_DIR="$BACKUP_DIR" \
  SHOTTR_ZH_SKIP_TCC=1 \
  SHOTTR_ZH_SKIP_LAUNCH=1 \
  SHOTTR_ZH_SKIP_PROCESS_CONTROL=1 \
    "$REPO_ROOT/install.sh" "$APP_PATH"
}

# A failure after files are deployed must restore the complete official app.
if SHOTTR_ZH_BACKUP_DIR="$BACKUP_DIR" \
   SHOTTR_ZH_SKIP_TCC=1 \
   SHOTTR_ZH_SKIP_LAUNCH=1 \
   SHOTTR_ZH_SKIP_PROCESS_CONTROL=1 \
   SHOTTR_ZH_TEST_FAIL_AFTER_DEPLOY=1 \
     "$REPO_ROOT/install.sh" "$APP_PATH"; then
  echo "installer failpoint unexpectedly succeeded" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
spctl --assess --type execute "$APP_PATH"
ROLLBACK_SHA="$(shasum -a 256 "$APP_PATH/Contents/MacOS/Shottr" | awk '{print $1}')"
[ "$ROLLBACK_SHA" = "$ORIGINAL_SHA" ]
[ ! -d "$APP_PATH/Contents/Frameworks" ]

run_installer

DYLIB="$APP_PATH/Contents/Frameworks/shottr_zh.dylib"
DICT="$APP_PATH/Contents/Resources/zh_dict.plist"
BIN="$APP_PATH/Contents/MacOS/Shottr"
[ -f "$DYLIB" ]
[ -f "$DICT" ]
[ "$(otool -L "$BIN" | grep -Fc '@executable_path/../Frameworks/shottr_zh.dylib')" -eq 2 ]
DYLIB_ARCHS="$(lipo -archs "$DYLIB")"
grep -Fwq arm64 <<<"$DYLIB_ARCHS"
grep -Fwq x86_64 <<<"$DYLIB_ARCHS"
DYLIB_BUILD="$(vtool -show-build "$DYLIB")"
grep -Fq 'minos 15.0' <<<"$DYLIB_BUILD"
codesign --verify --deep --strict "$APP_PATH"
if xattr -p com.apple.quarantine "$APP_PATH" >/dev/null 2>&1; then
  echo "quarantine attribute was not cleared" >&2
  exit 1
fi

MARKER="$APP_PATH/Contents/Resources/shottr_zh_backup_id"
[ -f "$MARKER" ]
BACKUP_APP="$BACKUP_DIR/$(sed -n '1p' "$MARKER")"
codesign --verify --deep --strict "$BACKUP_APP"
BACKUP_SIGNATURE="$(codesign -dv --verbose=4 "$BACKUP_APP" 2>&1)"
grep -Fq 'TeamIdentifier=2Y683PRQWN' <<<"$BACKUP_SIGNATURE"
spctl --assess --type execute "$BACKUP_APP"

# Reinstall must be idempotent and reuse the exact full-app backup.
run_installer
[ "$(otool -L "$BIN" | grep -Fc '@executable_path/../Frameworks/shottr_zh.dylib')" -eq 2 ]

SHOTTR_ZH_BACKUP_DIR="$BACKUP_DIR" \
SHOTTR_ZH_SKIP_TCC=1 \
SHOTTR_ZH_SKIP_LAUNCH=1 \
SHOTTR_ZH_SKIP_PROCESS_CONTROL=1 \
  "$REPO_ROOT/uninstall.sh" "$APP_PATH"

FINAL_LOADS="$(otool -L "$BIN")"
if grep -Fq shottr_zh <<<"$FINAL_LOADS"; then
  echo "injected load command survived uninstall" >&2
  exit 1
fi
[ ! -e "$DYLIB" ]
[ ! -e "$DICT" ]
[ ! -e "$MARKER" ]
[ ! -d "$APP_PATH/Contents/Frameworks" ]
codesign --verify --deep --strict "$APP_PATH"
FINAL_SIGNATURE="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
grep -Fq 'TeamIdentifier=2Y683PRQWN' <<<"$FINAL_SIGNATURE"
spctl --assess --type execute "$APP_PATH"
FINAL_SHA="$(shasum -a 256 "$BIN" | awk '{print $1}')"
[ "$FINAL_SHA" = "$ORIGINAL_SHA" ]

echo "official DMG end-to-end test passed on $(sw_vers -productVersion) / $(uname -m)"
