#!/bin/bash
#
# package-dmg.sh — Build boringNotch (Release) and pack it into a DMG.
#
# Usage:
#   scripts/package-dmg.sh              # build + create DMG in build/
#   scripts/package-dmg.sh --install    # also kill running instances and copy to /Applications
#   scripts/package-dmg.sh --open       # also launch the installed app (implies --install)
#
# Output:
#   build/BoringNotch-Toolbox.dmg
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_NAME="Boring Notch"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/BoringNotch-Toolbox.dmg"
STAGE_DIR="$BUILD_DIR/dmg-staging"

INSTALL=0
OPEN_APP=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --open)    INSTALL=1; OPEN_APP=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# Seed SwiftPM caches from the default DerivedData if the local one has no
# checkouts yet — a fresh fetch can stall for ages on slow networks.
DEFAULT_DD=$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/boringNotch-"* 2>/dev/null | head -1 || true)
if [[ ! -d "$DERIVED_DATA/SourcePackages/checkouts" || -z "$(ls -A "$DERIVED_DATA/SourcePackages/checkouts" 2>/dev/null)" ]]; then
    if [[ -n "$DEFAULT_DD" && -d "$DEFAULT_DD/SourcePackages/checkouts" && -n "$(ls -A "$DEFAULT_DD/SourcePackages/checkouts" 2>/dev/null)" ]]; then
        echo "==> Seeding SwiftPM cache from $DEFAULT_DD …"
        rm -rf "$DERIVED_DATA/SourcePackages"
        mkdir -p "$DERIVED_DATA"
        cp -R "$DEFAULT_DD/SourcePackages" "$DERIVED_DATA/"
    fi
fi

echo "==> Building Release (this can take a few minutes)…"
xcodebuild \
    -project "$REPO_ROOT/boringNotch.xcodeproj" \
    -scheme boringNotch \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    build CODE_SIGNING_ALLOWED=NO | tail -3

[[ -d "$APP_PATH" ]] || { echo "Build product not found at $APP_PATH" >&2; exit 1; }

echo "==> Staging DMG contents…"
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating DMG…"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" 2>&1 | grep -v deprecated || true
rm -rf "$STAGE_DIR"
echo "    DMG: $DMG_PATH"

if [[ "$INSTALL" -eq 1 ]]; then
    echo "==> Installing to /Applications…"
    pkill -x "$APP_NAME" 2>/dev/null || true
    pkill -9 -f "mediaremote-adapter.pl" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_PATH" /Applications/
    xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true
    echo "    Installed: /Applications/$APP_NAME.app"
fi

if [[ "$OPEN_APP" -eq 1 ]]; then
    echo "==> Launching…"
    open "/Applications/$APP_NAME.app"
fi

echo "==> Done."
