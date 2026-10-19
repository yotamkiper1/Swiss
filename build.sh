#!/bin/bash
# Builds Swiss.app into ./build. Run `./build.sh install` to also copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Stash"

# `./build.sh test` makes "Swiss Test.app": its own bundle id (own settings), own library, stashtest:// and no
# global shortcuts — for testing without touching the real Swiss.
# (Swiss was called Stash: its bundle id, library folders and stash:// links keep that name, so nothing moves.)
NAME="Swiss"
[[ "${1:-}" == "test" ]] && NAME="Swiss Test"

# Assembled and signed outside Desktop: iCloud keeps adding file attributes there, which codesign refuses.
STAGE="$(mktemp -d)"
APP="$STAGE/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Swiss"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ "$NAME" == "Swiss Test" ]]; then
    PB=/usr/libexec/PlistBuddy
    $PB -c "Set :CFBundleIdentifier com.yotamkiper.stash.test" "$APP/Contents/Info.plist"
    $PB -c "Set :CFBundleName Swiss Test" -c "Set :CFBundleDisplayName Swiss Test" "$APP/Contents/Info.plist"
    $PB -c "Delete :CFBundleURLTypes:0:CFBundleURLSchemes:1" "$APP/Contents/Info.plist"
    $PB -c "Set :CFBundleURLTypes:0:CFBundleURLName com.yotamkiper.stash.test" -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 stashtest" "$APP/Contents/Info.plist"
fi
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Built-in tools: the LAME MP3 encoder and the yt-dlp downloader.
[ -d Resources/tools ] && cp -R Resources/tools "$APP/Contents/Resources/"
xattr -cr "$APP"
codesign --force --options runtime --entitlements Resources/Swiss.entitlements --sign - "$APP" >/dev/null # Hardened Runtime: nothing can inject code into Swiss
rm -rf "build/$NAME.app"
mkdir -p build
ditto --noextattr "$APP" "build/$NAME.app"
echo "Built build/$NAME.app"

if [[ "${1:-}" == "install" ]]; then
    pkill -x Swiss || true
    pkill -x Stash || true # the app before it was renamed
    while pgrep -x Swiss >/dev/null || pgrep -x Stash >/dev/null; do sleep 0.2; done
    rm -rf /Applications/Stash.app /Applications/Swiss.app
    ditto --noextattr "$APP" /Applications/Swiss.app
    open /Applications/Swiss.app || { sleep 1; open /Applications/Swiss.app; }
    echo "Installed to /Applications/Swiss.app"
fi
rm -rf "$STAGE"
