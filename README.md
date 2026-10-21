<p align="center"><img src="docs/images/icon.png" width="128" alt="Swiss icon"></p>

# Swiss

**A pocket knife for your ideas.** Swiss is a macOS menu bar app for collecting what you find while you work — links, pictures, files, notes — and finding it again in a second. Everything stays on your Mac: no account, no cloud.

<p align="center">
  <img src="docs/images/window.png" width="720" alt="Swiss's window: projects in the sidebar, the board, the quick bar">
</p>
<p align="center">
  <img src="docs/images/canvas.png" width="360" alt="The Frame: a free canvas with its library">
  <img src="docs/images/welcome-tour.png" width="360" alt="The welcome tour">
</p>

## What it does

- **Projects as tabs.** Drop, paste or drag things in; organize with folders (Linker, PhotoBook, Notepad, Files), notes, tags and drag-and-drop. Copy and paste whole folders between projects.
- **Recent.** Optional capture of what you copy and screenshot; one tap keeps an item in a project. Off until you turn it on.
- **The magic wand.** Sorts a messy board into folders by kind.
- **Connected folders.** Work in any Finder folder like a project — rename, move, tag, sort. Changes happen in the real folder.
- **The Frame.** A free canvas above every app: pictures, notes, links, YouTube and video, zoom, pan, ⌘Z undo, and a library to pull items in from.
- **Convert.** Right-click → Convert: images (HEIC, PNG, JPEG…), video and audio (MP4, MP3…), documents to PDF. YouTube links can be saved as MP3/MP4.
- **Three sizes.** Pop-up, window, full screen — the green button steps up, orange steps down.
- **Safe by default.** Deleted items stay recoverable for 30 days; saves are crash-safe with automatic backups.

## Install

Requires macOS 14+ and Xcode (Swift 5.10+).

```bash
./build.sh            # builds build/Swiss.app
./build.sh install    # also copies it to /Applications and launches it
./build.sh test       # builds "Swiss Test", a separate copy for testing (own library and settings)
```

Open it from the menu bar icon or with **⌥Space**. The first launch shows a short welcome tour (Help → Welcome Tour to see it again).

## Essential keys

| Keys | Does |
|---|---|
| **⌥Space** | Open or close Swiss |
| **⌥⌘V** | Quick save what you copied, from any app |
| **⌘V** · **⌘C** | Paste into the current project or folder · copy cards and folders (pasting makes numbered copies, e.g. "Poster 2") |
| **⌘1 – ⌘6** | New note · folder · Linker · PhotoBook · Notepad · Files |
| **1 – 9** | Open the folder with that number |
| **⌃Tab** | Next project tab |
| **⌘A / ⌃A** · **⇧-click** | Select all · select a range |
| **Space** | Quick Look |
| **⌘⌫** · **⌘Z** | Delete · undo |
| **?** (bottom right) | Lists every button and key |

Tabs close with **×** (the project stays); projects are deleted from All Projects or the sidebar.

## Where your data lives

```
~/Documents/.Stash/            your library as real files and folders (hidden)
    <Project>/<Folder>/…         pictures and files, notes (.txt/.rtf), links (.webloc)
    .stash/                      Swiss's own data: library.json, backups, trash (30 days)
~/Library/Application Support/Stash/   settings and tools
```

Moving, renaming and deleting in Swiss does the same to the files. Very large files (default: over 250 MB) are linked, not copied, so they never fill your disk.

## Privacy and safety

- Everything stays on your Mac. No account, no servers, no analytics. Swiss only goes online for things you start: a saved link's title and picture, a picture dragged in from a web page, a YouTube video played on a canvas, a download you asked for, and updating the downloader.
- Capture of the clipboard, screenshots and downloads is **off** until you turn it on (Settings → Capture). Passwords and anything apps mark as private are never kept, and password managers are excluded. Recent keeps items 3 days by default.
- **Settings → Privacy → Require Touch ID** locks Swiss's windows behind Touch ID or your Mac password (macOS's own prompt). It locks again when the Mac locks or sleeps.
- Files are checked before they run (code-like files ask first), downloads are quarantined like Safari's, and the downloader runs without user config and only for web links. `swiss://` links from web pages are limited (5 per 10 s, text only, invisible characters removed) and never take a password from the clipboard.
- Saves are written in the background, checked, and swapped in atomically; the last good copy and hourly backups are kept.
- The full checklist and its status: [docs/SECURITY.md](docs/SECURITY.md).
- **Help → Report a Problem / Send Feedback** opens an email to the developer that you read and send yourself. Diagnostics are optional and hold versions, switches and counts, never library contents or file names.

## Updates

- Downloads in Recent: turn on **Downloads** at the top of Recent. New downloads land there, and anything you save to **Downloads ▸ Swiss** from any Save dialog does too. Finder: right-click ▸ Services ▸ **Add to Swiss Recent**. Chrome: the right-click extension in `extras/chrome`.
- Share: right-click anything (or use Share in the picture preview) for AirDrop, Mail, Messages and more; WhatsApp is added to the list.
- The "you copied…" banner now disappears after 15 seconds or when you move to another project or folder.
- Welcome tour on first launch.
- Copy/paste of cards and folders inside Swiss, with numbered names.
- The Frame: ⌘Z undo, a library panel, and a companion window.
- Connected folders in sync with Finder (arrange by name, kind, date, tags).
- Faster project switching and instant selection, even with 10,000 items.

## For developers

| Path | Contents |
|---|---|
| `Sources/Stash/` | The app (SwiftUI + AppKit): `Store.swift` (state), `Panel.swift` (windows, keys), `Canvas.swift` (the Frame), `ConnectedEdit.swift` (connected folders), `RecentStore.swift`, `Views/` |
| `Resources/` | Icon, Info.plist, entitlements, bundled `yt-dlp` and `lame` |
| `tools/film/` | The commercial film, made entirely in code (see its README) |
| `docs/` | Screenshots and design notes |

Swiss Test only: `stashtest://debug…` links drive test hooks (`DebugHooks.swift`); the real app ignores them. The bundle id, folder names and `stash://` scheme keep their old "Stash" names so existing libraries carry over; `swiss://` works too.

## Launch checklist

1. **Version**: `CFBundleShortVersionString` in `Resources/Info.plist` (now 1.0); raise `CFBundleVersion` for every build you publish.
2. **Apple Developer account** ($99/yr, developer.apple.com). In Xcode ▸ Settings ▸ Accounts, create a **Developer ID Application** certificate.
3. **Notary credentials**, once: `xcrun notarytool store-credentials swiss-notary --apple-id YOU --team-id TEAMID` (it asks for an app-specific password from appleid.apple.com and keeps it in the keychain).
4. **Sign, notarize, staple**: `SIGN_ID="Developer ID Application: Yotam Kiper (TEAMID)" ./build.sh notarize` → `build/Swiss-1.0.zip`, which opens on any Mac without a Gatekeeper warning.
5. **Apple silicon only** for now: the app and the bundled MP3 encoder are arm64. For Intel Macs, build with `--arch arm64 --arch x86_64` and bundle a universal `lame`.
6. **Downloader**: update `Resources/tools/yt-dlp` to the latest release before each launch (sites change often).
7. **Sign in with Apple / Google**: not in 1.0 (Swiss has no sync, so an account wouldn't do anything yet). It needs the Developer account (Apple), a Google Cloud OAuth client, and a server to check sign-ins. Never collect Apple or Google passwords in Swiss's own form.
