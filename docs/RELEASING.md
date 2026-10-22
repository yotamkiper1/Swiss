# Releasing Swiss

1. **Version.** Set `CFBundleShortVersionString` in `Resources/Info.plist` (now 1.0) and raise `CFBundleVersion` for every build you publish.
2. **Apple Developer account** ($99/yr, developer.apple.com). In Xcode ▸ Settings ▸ Accounts, create a **Developer ID Application** certificate.
3. **Notary credentials**, once: `xcrun notarytool store-credentials swiss-notary --apple-id YOU --team-id TEAMID`. It asks for an app-specific password from appleid.apple.com and keeps it in the keychain.
4. **Sign, notarize, staple:** `SIGN_ID="Developer ID Application: Yotam Kiper (TEAMID)" ./build.sh notarize` → `build/Swiss-1.0.zip`, which opens on any Mac without a Gatekeeper warning.
5. **Architectures.** Apple silicon only for now: the app and the bundled MP3 encoder are arm64. For Intel Macs, build with `--arch arm64 --arch x86_64` and bundle a universal `lame`.
6. **Downloader.** Update `Resources/tools/yt-dlp` to the latest release before each release (sites change often).
7. **Selling.** The website sells through a Lemon Squeezy hosted checkout: upload the zip to the product, then put its checkout link in `site/js/purchase.js` (see `site/README.md`).
8. **Accounts.** Sign in with Apple / Google is not in 1.0; Swiss has no sync, so an account would do nothing yet. It would need the Developer account, a Google Cloud OAuth client and a server to check sign-ins. Never collect Apple or Google passwords in Swiss's own form.
