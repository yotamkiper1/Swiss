# Swiss: silent product film (40 s, v4) — production brief

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
| 5e | Collect by drag and paste | Dropping or pasting into a board adds it: pictures (files, file promises or image URLs from a browser), links (a pasted or dropped web address), and text, which becomes a note. One drop or paste is one undo step. | Action. | `Ingest.swift:7–90, 156–186` |
| 5f | Three sizes | The green window button grows Swiss: **pop-up → window → whole screen**; orange steps back, red closes (Window menu: Pop-up ⌥⌘1, Full Screen ⌥⌘2, Frame ⌥⌘3). The pop-up is 300 × 400 pt. | Action. | `Views/WindowLights.swift:13–32`; `Views/WindowMode.swift:5–9`; `MainMenu.swift:211–216`; `Views/CompactView.swift:13`; `Views/WelcomeTour.swift:82–85` |

Not advertised in the film: Convert, YouTube MP3/MP4 download, Share, Deep Organize. They exist but would crowd the film.

## 2. Final on-screen copy (v4, the owner's script)

The owner's script, word for word. Each scene has a small red label and a big white title that rises line by line; the titles are the captions, so there is no separate subtitle line. Opening and closing sit on the icon's off-white, the rest on the dark stage. Scenes are revealed behind a red diagonal slash.

| Time | Small label | Main title | Supporting line |
|---|---|---|---|
| 0–4 | SWISS | A pocket knife for your ideas. | — |
| 4–9 | COLLECT | Found something worth keeping? | — |
| 9–14 | RECENT | Copied. Captured. Within reach. | Optional clipboard and screenshot capture. |
| 14–19 | MAGIC WAND | A little order. In one click. | — |
| 19–24 | CONNECTED FOLDERS | Your folders. A faster way in. | — |
| 24–32 | THE FRAME | Keep your references beside your work. | — |
| 32–36 | THREE SIZES | Just the space you need. | — |
| 36–40 | Swiss logo | Keep your ideas moving. | Collect. Organize. Keep working. |

In-UI strings come from the app: “Recent”, “kept 3 days”, “Copies”, “Screenshots”, “Keep”, “Kept in Mammoth” (`RecentStore.swift:422`), “Organized 7 items into 4 new folders” (`Store.swift:1021`), “Linker / PhotoBook / Notepad / Files”, “Connected”.

## 3. Timed storyboard (30 fps, 40.0 s = 1200 frames)

The film follows one project, **Mammoth**, an exhibition being put together.

| Time | Beat | What happens |
|---|---|---|
| 0–4 | Opening | The icon pops in with a red ring pulse, SWISS and the title rise, then the icon grows into the Swiss window (the Mammoth board) as the stage turns dark |
| 4–9 | Collect | A browser on Wikipedia's woolly mammoth page beside Swiss. Drag the infobox photo in, drag the address in (a link card), select two lines, ⌘C, click the board, ⌘V: a note |
| 9–14 | Recent | Copies and Screenshots are already on. ⌘C on a link and ⇧⌘4 for a screenshot: both arrive in Recent. Select the screenshot, Keep → “Kept in Mammoth” |
| 14–19 | Magic wand | One click: PhotoBook, Linker, Notepad and Files appear, the seven loose things fly into them, the flash holds, then a double-click opens PhotoBook (breadcrumb Mammoth › PhotoBook, three pictures) |
| 19–24 | Connected folders | Click Exhibit images under Connected; its files show. Rename “lyuba-baby-mammoth.jpg” → “Lyuba – hero print.jpg”, then a Finder window of the same folder slides in with the renamed row highlighted |
| 24–32 | The Frame | Someone is typing exhibit labels in an editor. The Frame comes up above it; drag the hero print in from its library, ⌘N for a note (“Under 60 words. Big type.”), ⌘V a tutorial link and play it, then click back into the editor and keep typing while it plays |
| 32–36 | Three sizes | The cursor clicks the green light twice: pop-up → window → full screen, the same Mammoth board throughout; the size pills follow |
| 36–40 | Closing | Off-white with drifting red crosses: icon and wordmark, “Keep your ideas moving.”, then Collect. Organize. Keep working. one by one |

Easing: cubic in-out for camera, cursor and wipes; ease-out with a light overshoot for icons; titles rise line by line.

### Where the film simplifies

- It is a faithful HTML rebuild, not a screen recording (the container can't run macOS).
- The Frame's tutorial is drawn as a neutral player. In the app a pasted YouTube link becomes YouTube's own embedded player (`Canvas.swift:334`); its picture here is a slow move across the Vienna museum photo.
- The Frame appears with an animation; in the app it opens from Window › Frame (⌥⌘3).
- The wand starts on a board with no kind folders, so it makes new ones. With such folders already there, the app first asks *Add to Existing* or *Make New Folders*.

## 4. Assets

- **Pictures:** six freely licensed pictures from Wikimedia Commons plus a Wikipedia capture. Authors and licenses are in `CREDITS.md`. None of the owner's personal photos, videos or file names are used any more.
- **Rebuilt in HTML (faithful demonstration, not a screen recording):** Swiss's pop-up, window, sidebar, Recent, tabs, board, folders, the Frame, and a Finder window. The container is Linux, so the macOS app can't run or be recorded here.
- **Repo:** `Resources/AppIcon-source.png` (logo), the app's colours and strings.
- **Font:** Inter stands in for SF Pro, and SF Symbols are simplified SVGs.
- **For a version with real captures:** on a Mac, run `./build.sh test` and use the `stashtest://debug…` hooks (`DebugHooks.swift`, `tools/film/`) to stage each screen.

## 5. What was rendered

- `swiss-film-1920x1080.mp4`: 1920×1080, 30 fps, 40.0 s (1200 frames), H.264 High, yuv420p, **no audio stream**.
- `swiss-film-1080x1920-vertical.mp4`: the same film for 1080×1920. Titles sit above the app (a 680-point-wide crop of each scene),.
- v1 (40 s), v2 (34 s) and v3 (43 s, then 40 s) are in git history.

To rebuild: `node render.mjs video out/swiss-film-1920x1080.mp4` and `node render.mjs video out/swiss-film-1080x1920-vertical.mp4 v`. This needs Node with Playwright, Chromium, ffmpeg and Inter.
