#!/bin/bash
# Builds Swiss.app into ./build. Run `./build.sh install` to also copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

# The project may sit in iCloud Drive (Desktop & Documents), which touches files while they compile ("modified during
# the build"). Compile from a private copy outside it instead.
WORK="$HOME/Library/Caches/SwissBuild"
mkdir -p "$WORK/src"
rsync -a --delete --exclude .build --exclude build --exclude .git --exclude docs --exclude tools --exclude Unused ./ "$WORK/src/"
# The test hooks (stashtest://debug…, DebugHooks.swift) are compiled into Swiss Test only: the real Swiss doesn't contain them.
BUILD=(-c release --build-path "$WORK/.build")
[[ "${1:-}" == "test" ]] && BUILD=(-c release --build-path "$WORK/.build-test" -Xswiftc -DSWISS_TEST)
(cd "$WORK/src" && swift build "${BUILD[@]}")
BIN="$(cd "$WORK/src" && swift build "${BUILD[@]}" --show-bin-path)/Stash"

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
    $PB -c "Delete :NSServices" "$APP/Contents/Info.plist" # the test app doesn't add a second "Add to Swiss Recent" to Finder's menu
    $PB -c "Set :CFBundleURLTypes:0:CFBundleURLName com.yotamkiper.stash.test" -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 stashtest" "$APP/Contents/Info.plist"
fi
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Built-in tools: the LAME MP3 encoder and the yt-dlp downloader.
[ -d Resources/tools ] && cp -R Resources/tools "$APP/Contents/Resources/"
xattr -cr "$APP"
# Signing. Without SIGN_ID it's signed for this Mac only ("-"). For other Macs, set SIGN_ID to your Developer ID, e.g.
#   SIGN_ID="Developer ID Application: Yotam Kiper (TEAMID)" ./build.sh notarize
# Hardened Runtime everywhere: nothing can inject code into Swiss or its tools.
SIGN="${SIGN_ID:--}"
STAMP=""; [[ "$SIGN" != "-" ]] && STAMP="--timestamp"
for tool in "$APP/Contents/Resources/tools/"*; do
    [[ -x "$tool" && ! -d "$tool" ]] || continue
    # yt-dlp unpacks its own Python libraries when it runs, so it alone may load libraries it signed itself.
    ENT=(); [[ "$(basename "$tool")" == "yt-dlp" ]] && ENT=(--entitlements Resources/tools.entitlements)
    codesign --force --options runtime $STAMP ${ENT[@]+"${ENT[@]}"} --sign "$SIGN" "$tool" >/dev/null
done
codesign --force --options runtime $STAMP --entitlements Resources/Swiss.entitlements --sign "$SIGN" "$APP" >/dev/null
codesign --verify --strict --deep "$APP"
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
if [[ "${1:-}" == "notarize" ]]; then
    # Once: xcrun notarytool store-credentials swiss-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID
    # (it asks for an app-specific password from appleid.apple.com and keeps it in your keychain).
    [[ "$SIGN" != "-" ]] || { echo "Set SIGN_ID to your Developer ID Application certificate first"; exit 1; }
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
    ZIP="build/Swiss-$VERSION.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-swiss-notary}" --wait
    xcrun stapler staple "$APP"
    rm -rf "build/$NAME.app" && ditto --noextattr "$APP" "build/$NAME.app"
    rm "$ZIP" && ditto -c -k --keepParent "build/$NAME.app" "$ZIP" # the stapled app, ready to put online
    spctl --assess --type execute -vv "build/$NAME.app"
    echo "Notarized: $ZIP"
fi
rm -rf "$STAGE"
