# Swiss: silent product film (40 s) — production brief

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

Not advertised in the film: Convert, YouTube MP3/MP4 download, Share, Deep Organize. They exist but would crowd 40 seconds.

## 2. Final on-screen copy

Captions (Inter Semibold, near-black on the light stage; one line each):

1. **Project material ends up everywhere.**
2. **Copy it. Swiss keeps it in Recent.**
   small: *Capture is opt-in · Settings → Capture*
3. **Keep what matters in a project.**
4. **One click sorts the board by kind.**
5. **The Frame stays on top while you work.**
6. **Connect a Finder folder. Edit the real files.**
7. **Everything for the project, in one place.**
8. End card: Swiss icon, wordmark **Swiss**, line **A pocket knife for your ideas.**, small: *For Mac · macOS 14 or later*

In-UI text is taken from the app’s own strings: “Recent”, “Keep”, “Kept in Poster Series”, “Organized 8 items into 4 new folders”, “Linker / PhotoBook / Notepad / Files”, “Connected”, “Search Poster Series”, “Photos, videos, links (YouTube plays here), text, files.”

## 3. Timed storyboard (30 fps, 40.0 s = 1200 frames)

| Time | Scene | Footage | Action | Caption | Transition |
|---|---|---|---|---|---|
| 0.0–4.6 | Problem | Mac desktop (neutral wallpaper): a browser with a reference page, Finder-style Desktop icons “poster_final_v2.png”, “Screenshot 09.14.png”, “brief (1).pdf”, “final final 2.psd”, two sticky notes | Very slow push-in (100→103 %) | 1 | Fade from white 0.6 s |
| 4.6–9.6 | Capture | Browser left, Swiss big window right showing **Recent** | Cursor clicks address bar, ⌘C key hint; a link row slides into Recent (“Link · Safari · now”); a moment later ⇧⌘4 hint and a Screenshot row appears | 2 + small note | Dip through the desktop (0.35 s out, 0.35 s in) |
| 9.6–13.6 | Keep | Same window, close-up 115 % on Recent | Cursor selects the screenshot row, clicks **Keep**; label becomes “✓ Kept in Poster Series”; flash bubble | 3 | Gentle scale |
| 13.6–21.0 | Wand | Big window, project tab **Poster Series** (pinned), an existing plain folder “Print shop” (number 1) and 8 loose cards (3 pictures, 1 link, 1 Google Docs link, 2 notes, 1 PDF) | Cursor to the wand, click. No kind folders exist yet, so there is no prompt; new **PhotoBook, Linker, Notepad, Files** folders appear (numbers 2–5) and the cards glide into them, the Google Doc into Files; “Print shop” is untouched; flash “Organized 8 items into 4 new folders” | 4 | Dip through the desktop |
| 21.0–28.6 | Frame | A design app window fills the screen; the Frame floats on top, library (Recent) on the left | Cursor drags a picture from the library onto the canvas; a YouTube link card plays with a progress bar; cursor clicks back into the design app — the Frame stays in front | 5 | Dip through the desktop |
| 28.6–34.6 | Connected folder | Big window: sidebar **Connected › Client Files**; a Finder window beside it showing the same folder | Cursor renames “brief (1).pdf” → “Brief.pdf” in Swiss; the Finder window updates the same name | 6 | Dip through the desktop |
| 34.6–37.4 | Organized | Big window with sidebar: Poster Series (pinned) selected, folders Print shop 1, PhotoBook 2, Linker 3, Notepad 4, Files 5 with counts, a few cards | Slow pull-back 104→100 % | 7 | Dip through the desktop |
| 37.2–40.0 | End | Off-white card (the icon's own background), Swiss icon, wordmark, line, small platform line | Icon, wordmark, line and platform line fade in one after another, 4 % settle, no bounce | 8 | Fade to end card 0.7 s |

Easing: cubic in-out for camera and cursor, ease-out for things arriving. No scale above 115 %, no shake, no flash frames, no particles.

## 4. Assets and recording needs

- **Used from the repo:** `Resources/AppIcon-source.png` (logo), the app’s colours (`Views/FolderViews.swift` kind colours, Finder-blue folders, accent blue), layout and strings from the source, `docs/images/*.png` as reference.
- **Rebuilt in HTML (faithful demonstration, not a screen recording):** the window, sidebar, tabs, Recent list, cards, folders, the Frame, a Finder window and a browser. The container is Linux, so the macOS app cannot run or be recorded here.
- **Font:** macOS uses SF Pro; the render uses **Inter** (closest open font installed here). On a Mac, swap in SF Pro for pixel-exact type.
- **Icons:** SF Symbols are Apple-only; simplified SVG equivalents are drawn inline.
- **Demo pictures:** generated gradients/posters in code (no stock).
- **YouTube:** shown as a generic player frame labelled youtube.com; no third-party video content or logo.
- **For a version with real captures:** on a Mac run `./build.sh test` and use the existing `stashtest://debug…` hooks (`DebugHooks.swift`, `tools/film/`) to stage each screen, then record 1920×1080 at 2× with the cursor visible. Needed shots: Recent receiving a link and a screenshot, Keep; the wand on a messy board; the Frame over another app with YouTube playing; a connected folder rename with Finder beside it. The HTML timing can be kept as the edit.

## 5. What was rendered

- `swiss-film-1920x1080.mp4`: 1920×1080, 30 fps, 40.0 s (1200 frames), H.264 High, yuv420p, **no audio stream**.
- `swiss-film-1080x1920-vertical.mp4`: the same film reframed for 1080×1920 (a 680-point-wide crop per scene with one calm move each; captions below the screen).
- Source: `tools/commercial/film.html` (all scenes, captions and timing; `?t=12.3` shows any moment, `?v=1` the vertical layout) and `tools/commercial/render.mjs` (headless Chromium → ffmpeg).

Rebuild: `node render.mjs video out/swiss-film-1920x1080.mp4` and `node render.mjs video out/swiss-film-1080x1920-vertical.mp4 v` (needs Node with Playwright, Chromium, ffmpeg, and the Inter font).
