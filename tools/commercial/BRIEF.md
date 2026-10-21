# Swiss: silent product film (43 s, v3) — production brief

Everything here was checked against the source on `main` (commit `9785414`). File references are to `Sources/Stash/`.

## 1. Verified feature table

| # | Your description | What the code actually does | Automatic or action? | Source |
|---|---|---|---|---|
| 1a | Capturing copied text, links, files | **Recent** is a temporary inbox. With *Capture what I copy* on, Swiss checks the clipboard every 0.8 s and adds text, links, pictures and files. Copied **files are only linked** (nothing copied) until you press **Keep**. Pictures are stored as a blob inside Recent. Repeats collapse into one entry (×2). Password managers and “concealed/transient” clipboard types are skipped. | **Off by default.** Once turned on (Settings → Capture) it is automatic. Moving into a project needs **Keep** (↩). | `RecentStore.swift:1–76` (model, defaults `clipboardKey: false`), `:170` `checkClipboard`, `:384` `keep`; `Views/CaptureSettingsView.swift:14–63` |
| 1b | Capturing screenshots | With *Capture screenshots* on, Swiss watches one folder (the one you chose, or macOS’s screenshot location) and adds only files macOS marks as screen captures. They stay where they are (linked) until **Keep**. Separately, pressing ⌥Space within 90 s of a screenshot saves it to the open project. | Off by default; then automatic into Recent. | `RecentStore.swift:219` `checkScreenshots`; `Screenshots.swift:23` `catchRecent` |
| 1c | “Quick save” | **⌥⌘V** (changeable) saves what’s on the clipboard into the current project, inside its matching Linker/PhotoBook/Notepad/Files folder if one exists, and shows a “Saved to …” bubble. Works with capture off. On opening Swiss after a copy, a “Link copied · Paste ⌘V” banner offers to save it. | Action (shortcut / Paste). | `QuickSave.swift:7`, `:33`; `Clipboard.swift:36` `prepareForClipboard`, `ClipboardBanner` |
| 1d | Retention | Recent keeps items **3 days by default** (1, 3, 7, 30 days, or until cleared) and up to **500 MB** by default; oldest go first. (A code comment saying “7 days” is stale.) | Automatic. | `RecentStore.swift:65, 75–76, 310` |
| 2 | Temporary project material, visible and easy to find; storage | Projects are **tabs** (pinned ones always have a tab). The library is a **real folder tree in `~/Documents/.Stash/`** (hidden): `<Project>/<Folder>/…`, notes as .txt/.rtf, links as .webloc; Swiss’s data in `.stash/`. Files under the limit (**250 MB** default) are **copied in** (an APFS clone when on the same disk, so no extra space until changed; a full copy from another disk). Bigger files are **linked**, not copied. Deleted things stay recoverable for 30 days. Search covers titles, notes, URLs, tags and text recognised in images. Right-click a tab → **Save to Mac…** keeps a live copy of a project in a folder you pick. | Saving is an action (paste/drop/Keep); the mirror and backups are automatic. | `Mirror.swift:3–18, 336`; `BigFiles.swift:6–36`; `Ingest.swift:119` (`COPYFILE_CLONE`); `Files.swift:19`; `Models.swift:13–14` (pinned), `:173` (`searchText`); `ProjectExport.swift:5` |
| 3 | Magic Wand | Called **the wand** / **Organize** (menu: *Organize Into Folders* ⌥⌘O; right-click: *Clean Up*). One click moves the **loose things** where you are into a folder for their kind: **links → Linker, pictures → PhotoBook, notes → Notepad, files → Files**. Google Docs/Sheets/Slides/Forms and OneDrive/SharePoint links go to **Files**. It works in the folder you’re in (default) or on the project board. If such folders exist it asks *Add to Existing* / *Make New Folders* (configurable). It never sorts things already inside folders. **Big window only** (not the pop-up or the Frame). **Deep Clean Up / Deep Organize** (Settings) goes through every folder level. In a connected folder the wand moves real files into PhotoBook, Linker, Notepad, **Media** (video/audio) and Files folders, documents (Office, iWork, PDF, Google) into Files; ⌘Z undoes. No AI, no content categories beyond these kinds. | Action (one click). | `Store.swift:939–1022` (`organizePlan`, `requestOrganize`, `autoOrganize`), `:1028` `deepOrganize`; `Models.swift:62, 224`; `Views/BoardView.swift:380–455`; `Views/RootView.swift:51–56`; `ConnectedEdit.swift:286`; `Views/WelcomeTour.swift:70–73` |
| 4 | Canvas | Called **the Frame**: a free canvas in its own window, separate from projects. Supports **pictures, notes (double-click), links (page title fetched), videos (a YouTube link becomes YouTube’s embedded player that plays on the canvas; video files play with the Mac’s own controls) and files** (shown as icons). Zoom 20–400 %, pan (Hand tool, H / Space-drag), select (V), resize, ⌘Z undo, **library panel** (Recent, All Items or a project) to drag things in. It is a **floating window above other apps**, on every Space. | Action (drop/paste/drag from library). | `Canvas.swift:6–31, 336–420, 425`; `Views/CanvasView.swift:165, 548–600`; `Views/CanvasLibrary.swift:3–6`; `Panel.swift:12, 38, 45` |
| 5a | Finder integration | Library is real files in `~/Documents/.Stash` (*Show in Finder* from the board and cards). **Folder kinds map to Finder colour tags** (Linker = Green, PhotoBook = Red, Notepad = Orange, Files = Gray) and colour tags sync to the files. Drag things out to Finder. | Automatic mirror; actions for reveal/drag. | `Mirror.swift:3, 356–358`; `Models.swift:234–255`; `Views/BoardView.swift:390` |
| 5b | Connected folders | **Connected** (sidebar heading, + or drop a folder on it). Work inside any Finder folder like a project: new folders and notes, drop/paste in, **rename**, **move**, **colour-tag**, **Move to Trash**, **the wand**, arrange by name/kind/date/tags. Changes happen **in the real folder**; Finder edits show up in Swiss. Nothing is copied into the library. ⌘Z undoes Swiss’s last change. (The header comment in `ConnectedFolders.swift` still says “read-only”; that is stale — editing is in `ConnectedEdit.swift`.) | Action. | `Views/Sidebar.swift:36–60`; `ConnectedEdit.swift:5–11`; `Views/ConnectedFolderView.swift:35–39`; `ConnectedMoves.swift:128–180` |
| 5c | The app’s own organization system | Projects (tabs) → folders (Classic, Linker, PhotoBook, Notepad, Files) → items (link, image, text, file), plus notes, colour tags and #tags. Folder icon = Finder-blue folder with a coloured kind dot. | — | `Models.swift:3–60, 266`; `Views/FolderViews.swift:5–88` |
| 5d | “Priority folders” | **No feature with that name.** The closest real features: the **first nine folders on a board are numbered**; pressing **1–9** opens that folder and **⌥1–⌥9** puts the selection into it. And **pinned projects** (Pin Tab) always keep a tab and sort first. The film shows numbered folders but does not call them “priority folders”. | Automatic numbering; pinning is an action. | `Views/BoardGrid.swift:126`; `Views/FolderViews.swift:135–160`; `Panel.swift:321–355`; `Views/Sidebar.swift:15–17`; `Views/AllProjects.swift:23, 156–165` |

| 5e | Three sizes | The green window button grows Swiss: **pop-up → window → whole screen**; orange steps back, red closes (Window menu: Pop-up ⌥⌘1, Full Screen ⌥⌘2, Frame ⌥⌘3). The pop-up is 300 × 400 pt. | Action. | `Views/WindowLights.swift:13–32`; `Views/WindowMode.swift:5–9`; `MainMenu.swift:211–216`; `Views/CompactView.swift:13`; `Views/WelcomeTour.swift:82–85` |

Not advertised in the film: Convert, YouTube MP3/MP4 download, Share, Deep Organize. They exist but would crowd the film.

## 2. Final on-screen copy (v3)

The style follows the owner's second reference. Most of it plays on a dark, warm stage, with a red numbered eyebrow, big white lines that rise into place, a grey line and a few chips; the intro and outro sit on the icon's off-white. Scenes are revealed behind a red diagonal slash.

| # | Eyebrow | Headline | Grey line | Chips / extras |
|---|---|---|---|---|
| Intro | — | Icon, a red ring pulse, **Swiss** slides out from behind the icon | *A pocket knife for your ideas.* | — |
| Opener | YOUR IDEAS ARE | **scattered.** → **links.** → **screenshots.** → **files.** (over drifting cards) | — | — |
| 01 | Menu bar | One click away. | Lives in your menu bar. Always ready. | — |
| 02 | Recent | Copy. Capture. Keep. | Everything you copy or screenshot lands here, ready to keep. | Link copied · Text copied · Screenshot captured; *Capture is opt-in · Settings → Capture* |
| 03 | Projects | Tabs for every idea. | Folders, notes, pictures and links. One calm place. | — |
| 04 | The wand | One tap. No mess. | Links, pictures, notes and files sort themselves into folders. | Linker · PhotoBook · Notepad · Files |
| 05 | Connected folders | Finder, inside Swiss. | Rename, move, tag and sort. Finder follows along. | — |
| 06 | The Frame | A canvas above it all. | Pull anything in from your library. Move it, zoom in, undo. | ⌘ Z keycaps · Undo, any time |
| 07 | One click, three sizes | Make it yours. | Green grows Swiss: the pop-up, the window, then the whole screen. | POP-UP · WINDOW · FULL SCREEN |
| Privacy | — | ~~No account.~~ ~~No cloud.~~ **Stays on your Mac.** (red lock) | — | README: “no account, no cloud” |
| Outro | — | Icon, **Swiss** | *A pocket knife for your ideas.* | FOR MACOS 14 OR LATER |

In-UI strings come from the app: “Recent”, “kept 3 days”, “Copies”, “Screenshots”, “Keep”, “Kept in Mammoth”, “Organized 7 items into 4 new folders” (`Store.swift:1021`), “Linker / PhotoBook / Notepad / Files”, “Connected”, “New”.

## 3. Timed storyboard (30 fps, 43.0 s = 1290 frames)

| Time | Beat | What happens |
|---|---|---|
| 0.0–2.7 | Intro | Icon pops in with a small overshoot, a red ring pulses out, the wordmark slides out from behind the icon, then the line fades up |
| 2.7–6.4 | Scattered | Red slash. About 30 cards drift at different depths (blurred when far): the Commons pictures, coloured poster cards, ghost cards. The word under “YOUR IDEAS ARE” rolls through four words; the camera flies through the cards into black |
| 6.4–9.8 | 01 Menu bar | The desktop fades up. The cursor clicks the knife in the menu bar; the pop-up opens with the Mammoth tab, its folders and a few things; rings on the icon, then the pop-up |
| 9.8–15.0 | 02 Recent | A link, a text and a screenshot arrive in Recent, each with a ring and a chip. Select the screenshot, Keep → “Kept in Mammoth”; push in on the list |
| 15.0–18.4 | 03 Projects | The cursor clicks through the tabs Mammoth → Showreel → Thesis → Mammoth; each board swaps in |
| 18.4–23.2 | 04 Wand | One click: PhotoBook, Linker, Notepad and Files appear, seven cards fly in (Google Doc and PDF → Files), flash; push in on the folders |
| 23.2–27.6 | 05 Connected | Swiss › Connected › Exhibit images, with a Finder window of the same folder. Rename “lyuba-baby-mammoth.jpg” → “Lyuba – hero print.jpg”; the Finder row follows |
| 27.6–32.4 | 06 Frame | Drag the skull from the library onto the canvas, play a local video with the Mac's controls, then ⌘Z takes the drop back |
| 32.4–35.8 | 07 Sizes | The cursor clicks the green light twice: the pop-up grows to the window, then to the whole screen; the size pills follow |
| 35.8–38.8 | Privacy | A red lock drops in. “No account.” and “No cloud.” are struck through, then “Stays on your Mac.” |
| 38.8–43.0 | Outro | Off-white with drifting red crosses: icon, wordmark, line, FOR MACOS 14 OR LATER |

Easing: cubic in-out for camera, cursor and wipes; ease-out with a light overshoot for icons; titles rise line by line.

## 4. Assets

- **Pictures:** six freely licensed pictures from Wikimedia Commons plus a Wikipedia capture. Authors and licenses are in `CREDITS.md`. None of the owner's personal photos, videos or file names are used any more.
- **Rebuilt in HTML (faithful demonstration, not a screen recording):** Swiss's pop-up, window, sidebar, Recent, tabs, board, folders, the Frame, and a Finder window. The container is Linux, so the macOS app can't run or be recorded here.
- **Repo:** `Resources/AppIcon-source.png` (logo), the app's colours and strings.
- **Font:** Inter stands in for SF Pro, and SF Symbols are simplified SVGs.
- **For a version with real captures:** on a Mac, run `./build.sh test` and use the `stashtest://debug…` hooks (`DebugHooks.swift`, `tools/film/`) to stage each screen.

## 5. What was rendered

- `swiss-film-1920x1080.mp4`: 1920×1080, 30 fps, 43.0 s (1290 frames), H.264 High, yuv420p, **no audio stream**.
- `swiss-film-1080x1920-vertical.mp4`: the same film for 1080×1920. Titles sit above the app (a 680-point-wide crop of each scene), and the menu bar scene runs full height.
- v1 (40 s) and v2 (34 s) are in git history.

To rebuild: `node render.mjs video out/swiss-film-1920x1080.mp4` and `node render.mjs video out/swiss-film-1080x1920-vertical.mp4 v`. This needs Node with Playwright, Chromium, ffmpeg and Inter.
