# Swiss: silent product film (34 s, v2) — production brief

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

Not advertised in the film: Convert, YouTube MP3/MP4 download, Share, Deep Organize. They exist but would crowd 34 seconds.

## 2. Final on-screen copy (v2)

Each beat has a red eyebrow, one headline and at most a few chips (the reference film's style). Inter, near-black on the light stage.

| Eyebrow | Headline | Chips |
|---|---|---|
| — | Your project lives in **browser tabs. / Downloads. / screenshots.** (the red word cycles) | — |
| 01 · Recent | Copy it once. It lands in Recent. | + Link captured · + Screenshot captured · *Opt-in · Settings → Capture* |
| 02 · Keep | Keep what matters in a project. | + Moved into Mammoth · *Recent clears after 3 days* |
| 03 · The wand | One click sorts the board by kind. | + Pictures → PhotoBook · + Links → Linker · + Notes → Notepad · + Files & docs → Files |
| 04 · The Frame | A canvas that stays on top. | + Drag in from your library · + Videos play in place |
| 05 · Connected folders | Work right inside any Finder folder. | + Rename, move, tag · + Finder follows along |
| 06 · On your Mac | Everything in one place. | + No account · + No cloud (README: “no account, no cloud”) |
| End card | Swiss icon, **Swiss**, *A pocket knife for your ideas.*, *For Mac · macOS 14 or later* | — |

In-UI text uses the app's own strings: “Recent”, “kept 3 days”, “Copies”, “Screenshots”, “Keep”, “Kept in Mammoth”, “Organized 9 items into 4 new folders” (`Store.swift:1021`), “Linker / PhotoBook / Notepad / Files”, “Connected”.

## 3. Timed storyboard (30 fps, 34.0 s = 1020 frames)

| Time | Beat | What happens | Techniques |
|---|---|---|---|
| 0.0–3.6 | Problem | Desktop: Chrome on the real Wikipedia *Woolly mammoth* page (tabs: that page and “Exhibition text – Google Docs”), Finder **Downloads** with real names (the project folder, menu-auditorium.jpg, enjoy_the_show!_v1 (1080p).mp4, Stash-Design-and-Features.pdf), two screenshots on the desktop | Word-cycling headline; a red ring moves Chrome → Downloads → screenshots in step with the word |
| 3.6–9.8 | Recent → Keep | Click the address bar, ⌘C: a link row arrives in Recent (“en.wikipedia.org · Chrome · now”). ⇧⌘4 over the skeleton photo: a screenshot row arrives with that crop as its thumbnail. Zoom 120 % on Recent, select it, **Keep** → “Kept in Mammoth” | Key hints, red ring on each new row, chips as each thing lands |
| 9.8–15.8 | Wand | Project **Mammoth** (pinned tab) with the plain folder “Print shop” and 9 loose cards: five of the user's pictures, the Wikipedia link, the Google Doc, the video file, a note. Wand click: PhotoBook, Linker, Notepad, Files appear; cards fly in (video and doc → Files); flash; zoom on the folders | Ring on the wand, then on the new folders; four mapping chips |
| 15.8–22.2 | Frame | Chrome fills the screen; the Frame floats over it with the Mammoth library. Drag picture #3 onto the canvas; play the local video with the Mac's own controls (real frames of enjoy_the_show, 10 fps); click back into Chrome: Chrome becomes active, the Frame stays in front | Push-in on the Frame, ring on the Frame at the end |
| 22.2–27.4 | Connected folder | Finder list of the real folder (its 10 real image files) beside Swiss › Connected with real thumbnails #1–#6. Rename #3 to “Mammoth #3 – print.jpg” in Swiss; Finder updates the row and date | ↩ hints, ring on the Finder row |
| 27.4–30.6 | Organized | Mammoth board: Print shop 6, PhotoBook 5, Linker 1, Notepad 1, Files 2, a few cards | Slow pull-back 108 → 100 % |
| 30.15–31.0 | Wipe | A red diagonal wipe crosses the stage | From the reference film |
| 30.6–34.0 | End card | Icon, wordmark, line, platform line arrive one after another | Ease-out, no bounce |

Scenes dip through the shared wallpaper (0.3 s). Cubic in-out for camera and cursor, ease-out for arrivals; no zoom above 120 %.

## 4. Assets

- **The user's own material** (`tools/commercial/assets/`, from the connected Mac; **kept out of git**, since the repo is public — it's in the project files, and `assets/names.js` holds the real file names): pictures #1–#6 and #9 of the mammoth series (downscaled to 1200 px), menu-auditorium.jpg, 150 frames of enjoy_the_show!_v1 (1080p).mp4 (480×240, from 96 s), and real file and folder names from Downloads and the project folder.
- **Chrome:** a real headless-Chromium capture of en.wikipedia.org/wiki/Woolly_mammoth (`wiki.jpg`) and a crop of its skeleton photo (`wiki-skeleton.jpg`), shown inside a Chrome-style window. The user's own Chrome was not screen-recorded.
- **Deliberately left out:** personal documents seen in Downloads (CV, payment receipt, letters, an applications tracker).
- **Rebuilt in HTML (faithful demonstration, not a screen recording):** Swiss's windows, sidebar, Recent, cards, folders, the Frame, Finder. The container is Linux, so the macOS app can't run or be recorded here.
- **Repo:** `Resources/AppIcon-source.png` (logo), the app's colours and strings.
- **Font:** Inter stands in for SF Pro; Hebrew falls back to Liberation Sans. SF Symbols are drawn as simplified SVGs.
- **For a version with real captures:** on a Mac run `./build.sh test` and use the `stashtest://debug…` hooks (`DebugHooks.swift`, `tools/film/`) to stage each screen, then record at 2× with the cursor visible; this HTML timing can serve as the edit.

## 5. What was rendered

- `swiss-film-1920x1080.mp4`: 1920×1080, 30 fps, 34.0 s (1020 frames), H.264 High, yuv420p, **no audio stream**.
- `swiss-film-1080x1920-vertical.mp4`: the same film reframed for 1080×1920 (a 680-point-wide crop per scene, captions below).
- Both decode cleanly end to end; the only still stretch is the 2.6 s end-card hold.
- v1 (40 s) is in git history.

Rebuild: `node render.mjs video out/swiss-film-1920x1080.mp4` and `node render.mjs video out/swiss-film-1080x1920-vertical.mp4 v` (Node with Playwright, Chromium, ffmpeg, Inter).
