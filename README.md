<p align="center"><img src="docs/images/icon.png" width="128" alt="Swiss icon"></p>

# Swiss

<p align="center">
  <img src="docs/images/window.png" width="720" alt="Swiss's big window: projects in the sidebar, the board, the quick bar">
</p>
<p align="center">
  <img src="docs/images/canvas.png" width="400" alt="The Frame: a free canvas with its library">
  <img src="docs/images/welcome-tour.png" width="400" alt="The welcome tour">
</p>

Swiss (formerly Stash) is a tiny macOS menu bar app for collecting project references fast: links, images, files, ideas and sentences.

## Latest tweaks

- **The commercial**: an 80-second film with voice-over, music, sound effects, zooms and transitions, made entirely in code (see `tools/film/`).

- **Welcome tour**: the first time Swiss opens, a small animated window walks through its tools page by page. It moves on by itself; **Stay** holds a page, ‹ and Next step through, Skip closes. Help → Welcome Tour shows it again.

- **Tabs only close.** × (or Close Tab) closes a project's tab — it stays closed until you open the project again; with no tabs left you're on Recent, which is always there. Connected folders' × works the same.
- **Projects are deleted from the lists**: the trash icon that shows when you point at a project in All Projects or the sidebar (it asks first). Unsorted can be deleted too — its things go to Recently Deleted.

- **Canvas undo**: ⌘Z steps back through every change on the canvas (adding, moving, resizing, deleting, editing, Clear); ⇧⌘Z redoes.
- **Canvas library rows**: a small picture or icon for each thing, a soft gray bar on the one you click, Space to look at it (Quick Look), drag it in or double-click to add.
- **Swiss beside the canvas** (the window-plus button on the Frame's top row): Swiss's pop-up opens next to the Frame and can grow to the window and full screen. It has no Frame button of its own; closing it leaves the canvas as it was, and closing the canvas closes it too.

- **Copy & paste cards and folders inside Swiss**: ⌘C, then ⌘V in any project, folder or window makes copies there (folders with everything inside). A name that's taken gets a number: "Poster 2.jpg", "PhotoBook 2", then 3… Other apps still get the files, text and links.

- **The Frame's library** (the sidebar button on its top row): Recent, All Items or any project down the side — drag things onto the canvas, or double-click to drop one in the middle.
- **Recent**: ⌘A / ⌃A selects everything, ⇧-click selects a range.
- **No new notes or folders in Recent or All Items** (the New buttons are gray there). **Clear in All Items** deletes everything it lists from its project (⌘Z undoes it); connected folders aren't touched. Clear in Recent empties Recent.

- **Faster project switching.** The bottom bar no longer builds four versions of itself on every change to pick the one that fits (about 150 → 55 ms per switch). Connected folders show their last listing at once, then refresh.
- **⇧-click ranges everywhere**: All Items, every project (also after a box or ⌘A), and connected folders.
- **Renaming on a selected row**: the name box turns light gray with a thin outline and dark text, so it stands out from the blue bar.
- **MP3 / MP4 quick buttons only on YouTube links.** Other video links and video / sound files have them in the right-click menu.
- **Recent keeps things for** 1 day, 3 days (the default), a week, 30 days, or until you clear it (Settings → Capture).
- **Screenshots reach Recent in under 0.2 s** (the folder is watched instead of checked every 2 s).

- **Menu bar icon** redrawn from the new logo: the handle with its rivet, the blade and the little tool, in one color.
- **Projects stay put in the sidebar.** Pinned first, then in the order they were made, like the tabs; picking one no longer moves it to the top.

- **Video controls on the canvas work.** A player's own controls (volume, timeline, YouTube's buttons) get the mouse: the card's click / drag / right-click no longer sit on top of it. Click a player to select it; move it and right-click it by its grip bar. A YouTube player no longer reloads whenever the canvas redraws (hovering, selecting), which had been resetting its volume bar.

- **Selecting is instant.** Each card and folder watches only whether it's selected, so a click or a box redraws just the tiles that change (about 0.5 ms, down from about 30 ms for a whole-window redraw). The box selects live as you sweep it, like Finder.
- **List view box selection fixed.** Row positions are worked out from the list itself, so every row (PDFs, folders, rows off screen) is caught, and nothing lights up below the list. In List view, drag from beside a row's name to start a box.
- **New Folder with Selection.** Make a new folder (or Linker / PhotoBook / Notepad / Files) while things are selected and they go inside it, in projects and in connected folders.

- **Icon**: your red Swiss knife picture (Resources/AppIcon-source.png), sized and rounded like a macOS icon by `swift Resources/icon-from-image.swift Resources/AppIcon-source.png Resources/AppIcon.icns`; the menu bar shows a knife in one color.
- **🔴🟠🟢 in the top-left corner**, like Finder: in the pop-up before the tabs, in the big window above the sidebar
  (before the tabs when the sidebar is hidden), in the Frame on its top row. The lock and ⧉ Frame buttons sit in the
  tools row. A small **⚙︎ Settings** button is at the bottom right, next to ?, in the pop-up and the big window.
- **Smoother**: resizing and moving things on the Frame's canvas no longer saves or redraws on every mouse move (a
  playing video is scaled while you resize and re-laid out once at the end); drawing a selection box redraws only the
  box; full screen (green) goes straight to its size instead of animating the whole board.
- **Dragging** a tile hides it while its picture follows the pointer (no gray copy left behind).
- **A delete sound**: the Mac's "move to Trash" sound, once per delete — a batch is one sound.
- **Folder kinds**: Classic, Linker, PhotoBook, Notepad, Files (Kraft, Pastel and Midnight are gone; such folders are
  Classic now).
- **Smaller pop-up** (300 × 400).
- **Hebrew in notes** goes to the right by itself as you type (each paragraph follows its language).
- **⌘A / ⌃A** select everything in All Items and tag lists too.
- **Folders are blue**, like Finder's: a plain folder is just the blue folder; Linker, PhotoBook, Notepad and Files have
  their colored dot on it.
- **Arrange By in a connected folder arranges the real folder in Finder too** (None → not arranged, Name, Kind, Tags;
  Date Added → Date Created, the closest Finder lets apps set). The first time, macOS asks to let Swiss control Finder.
- **The selection box** highlights what it touches as you drag and selects it when you let go — smooth on big boards.
  The Frame's canvas has **Select (V)** and **Hand (H)** tools: with Select, drag on empty space to draw a box; with
  Hand (or holding Space) drag to move around.
- **Arrow keys** in List view and Recent move without stutter (instant scrolling; Recent follows the selection).
- A smaller menu bar icon.

## Polish pass (design, UX, speed, space)

- **Tabs**: the × on a project tab now **closes the tab** (like a browser) — the project stays in the sidebar, ⌄ and the
  Go menu, and opening it brings the tab back. **Delete Project…** is on right-click. (The old × deleted the project,
  which was easy to do by accident with Chrome-style tabs.)
- **Folder kinds in Finder**: Linker, PhotoBook, Notepad, Files (and Kraft, Pastel, Midnight) are normal Finder folders
  with their kind's **color tag** — Green, Red, Orange, Gray (Yellow, Purple, Blue). Made in a connected folder, in
  Swiss's folder in Documents, or dragged out to Finder, a folder keeps its color; in a connected folder, a Finder folder's
  color tag shows as that kind's dot.
- **Calmer board**: MP3 / MP4 buttons show over a tile while you point at it (or it's selected), so every tile is the same
  size. In Recent, the board's view options and the wand are gray (they don't apply there). Recent's capture switches
  are lit when on and crossed out when off.
- **Settings** has tabs — General · Capture · Files · Shortcuts · Organize · Tools — and left-aligned explanations.
- **The Frame (canvas)**: press, hold a moment, then drag on empty space (or ⇧-drag) to **draw a box that selects**;
  ⌘- or ⇧-click adds and removes; **⌘A / ⌃A** selects everything (⌃-click is the Mac's right-click). A note's text grows
  with the note.
- **Faster**: Arrange By works out each thing's name once instead of on every comparison (tab switches with 1,000 things
  on the board got ~20 % faster); the board reports its scroll position directly.
- **Removed**: the old floating view, the ··· menu (it's all in the menu bar now), the ❝ quotes view and its layout,
  the capture question card, and other leftovers.

## Convert (right-click → Convert)

A new file is made next to the original (which is never changed) — in a project as a new card, in a connected folder
or for a Recent file right beside it:

- **Pictures**: JPG · PNG · HEIC · TIFF (iPhone HEIC photos too) · PDF · Smaller (2048 or 1024 px, keeping the format).
  Several pictures selected → **Make PDF of N Pictures** (a page each).
- **Videos**: MP4 · MOV · M4V · Smaller (1080p, 720p) · Smaller file (HEVC, same look) · Sound only (M4A); MP3 as before.
- **Sound**: M4A (and MP3).
- **Documents**: Word (.docx, .doc), RTF, text, OpenDocument text, web pages → PDF.
- All with the Mac's own frameworks (video on its hardware encoder), one heavy conversion at a time, after checking for
  free space. Tested: JPG→PNG, →1024 px, HEIC→JPG, picture→PDF, MJPEG→720p H.264, →HEVC, Word→PDF (Hebrew included).

**Documents are recognized**: Office (Word, Excel, PowerPoint), iWork (Pages, Numbers, Keynote), OpenDocument, PDF
and Google Drive files go with **Files** when organizing; Google Docs / Sheets / Slides / Forms links (and Office on
the web) show as documents in their colors and are organized with Files too.

**Recent** entries have the cards' tools: Open, Quick Look, Get Info, MP3 / MP4 (links: Keep & Download), Convert.

## Connected folders you can change

A connected folder now works like a project — but it's the real folder, so Finder and Swiss always match:

- **New Folder** (⌘2, or the folder+ button), **New Note** (⌘1 — saved as a .txt there), drop or paste (⌘V) things
  in (files are copied in, pictures saved, links become .webloc files that open from Finder too, text a .txt note).
- **Rename** (Return, or right-click), **Move to Trash** (⌘⌫ — Finder's Put Back works too), **⌘Z** undoes Swiss's
  last change. Right-click also has Copy, **Tags** (real Finder tags), **Put in Folder**, **MP3 / MP4** (made next to
  the file), **Move to Project**, Reveal in Finder, Quick Look.
- **Drag** like on the board: onto a folder (moves it in), onto the path at the top (moves it back up), onto empty space
  (it stays there — Arrange By "None" keeps where you put things), onto a **project tab** (moves it into that project),
  or out of the window — to the Desktop or a Finder folder it **moves**, like in Finder (hold ⌥ to copy).
- From a project, drag cards onto a connected folder's **tab** to move them out of Swiss into that folder.
- The **wand** (full screen) sorts loose files into PhotoBook, Linker, Notepad, Media and Files folders — real ones.
- Where tiles sit is remembered by Swiss (not written into your folder). Only the connected folder is ever touched.

## Icon

The app icon is a half-open pocket knife — red handle, cream rivet, dark blade — with no background; the menu bar shows
the same knife in one color (so it fits light and dark menu bars). `Resources/make-icon.swift` draws the app icon.

## The Frame: a free canvas

The Frame (⧉ next to the lock, or Window → Frame ⌥⌘3) stays on top of every app and is its own tool — no projects,
no toolbars, just a canvas, like a Miro board:

- Drop or paste (⌘V) anything: photos, videos (a YouTube link becomes a player that plays right there; video files
  play with the Mac's own controls), links (with the page's title), text, files. Double-click empty space for a note.
- Move around: drag empty space or two-finger scroll; zoom with a pinch, ⌘-scroll, ⌘+ / ⌘− or the − % + buttons
  (the % shows everything, ⌘0). Drag things to move them (videos by the bar on top), drag the blue corner to resize,
  arrows nudge, ⌫ deletes, double-click opens or edits, right-click for Copy / Show in Finder / Bring to Front.
- 🗑 Clear (two clicks) empties it — **Undo Clear** for 10 seconds. New things take the nearest free spot.
- Select something and drag its **sizer** (the blue corner with arrows) to make it bigger or smaller — or press
  **+ / −**, or right-click → **Bigger / Smaller**. Right-click → **Name…** gives it a name, shown under it.
- ▭ **Reframe**: draw on the screen where the Frame should be. The lock keeps it in place.
- It's saved by itself (`.stash/canvas.json` and `.stash/canvas/`): pictures are cloned in (no extra space on the same
  disk); big files from another drive stay linked. Only what's on screen is drawn. Settings → Storage shows its size.

## Latest: window buttons, menu bar, tabs, dragging, safety

- **Window buttons** (top-left of the pop-up, the big window and the Frame) — levels, small to big:
  🔴 closes the window (Swiss stays in the menu bar; Quit is ⌘Q) · 🟠 a level smaller · 🟢 a level bigger — pop-up → the window → full
  screen (fills the screen); the Frame's green opens the window, its orange the pop-up; gray when there's no further level · 🔒 locks the window where it is (one click on, one off; locked shows orange; right-click for
  **Draw Frame…**) · ⧉ opens the Frame (lit there; click to leave it).
- **The Mac menu bar** has the tools now — Swiss (Settings, catching copies/screenshots, Quit), File (new note/folder/
  Linker/PhotoBook/Notepad/Files ⌘1–⌘6, New Project ⌘T, Save From Clipboard ⇧⌘V, Connect a Folder, Show in Finder),
  Edit (Undo/Redo, Copy, Paste, Select All, Rename, Get Info ⌘I, Delete, Recently Deleted), View (Icons/List,
  Arrange By, sidebar, frame zoom, Organize — full screen only), Go (Recent, All Items, every project ⌃⌘1–9, connected
  folders, Back ⌘[), Window (Pop-up ⌥⌘1 · Full Screen ⌥⌘2 · Frame ⌥⌘3 · Lock ⌥⌘L · Draw Frame) and Help. Clicking a
  Swiss window brings Swiss to the front so its menus show (dropping things in from other apps doesn't).
- **On the windows** only what you use right there: window buttons, where things go, Icons/List and Arrange By — plus
  search, sidebar and the magic wand in full screen. The wand (and Clean Up) are full-screen only. The ❝ full-card view is gone.
- **Tabs like Chrome**: every project has a tab; they shrink to share the room, the open one stays readable, and past
  the smallest size the strip scrolls sideways (⌄ lists all). Connected folders get their own **teal tab** (drive icon)
  that stays until you close it (× — the folder stays connected); the folder view and its sidebar row have a × too.
- **Drag from anywhere to a tab**: cards and folders from the board, things from Recent, files from other apps — drop
  on a project tab (or a sidebar project) to put them in that project. **Recent** rows drag out to other apps
  (the real file, the link or the text; several at once) and onto tabs. Notes you write aren't added to Recent; in
  Recent, the label under the tabs says "Recent".
- **Space on a folder opens it** (on a file: Quick Look; on a note: edit) — and Space previews in All Items too.
- **Notes**: the editor's first menu sets the line you're on as **Title**, **Subtitle** or Body. Hebrew (and Arabic)
  start from the right — in the editor, and in notes on the Frame.
- **Safety**: files that can run code (apps, scripts, installers, shortcuts to them) are never opened without asking —
  "Show in Finder" is the default. Saved links open only if they're web or mail links; anything else asks. The
  downloader gets web links only, with `--` before the link and `--ignore-config` (so no link or settings file can add
  options that run commands). Downloads are marked as downloaded (quarantine), like Safari's. `swiss://add` text is
  capped. Swiss is signed with the Hardened Runtime. Test hooks exist only in Swiss Test.
- **Renamed to Swiss.** The bundle id, `~/Documents/.Stash`, Application Support/Stash and `stash://` keep their old
  names on purpose, so your library, settings and links carry over; `swiss://` works too.

## Build & run

```bash
./build.sh            # builds build/Stash.app
./build.sh install    # also copies it to /Applications and launches it
```

Requires macOS 14+ and Xcode (Swift 5.10+).

## Stash is a folder

Everything lives in **~/Documents/.Stash** (a hidden folder — right-click the menu bar icon → *Open Stash Folder*):

    ~/Documents/.Stash/
        Not Selected/          things in no project
        <Project>/             each project
            PhotoBook/         each folder (folders inside folders are subfolders)
            Files/tv.mp4       pictures and files are real files
            Idea.txt / .rtf    notes (formatted notes are .rtf)
            Are.na.webloc      links
        .stash/                Stash's own data

Moving, renaming and deleting in Stash does the same to the files. Deleted files wait in `.stash/trash` for 30 days
(Recently Deleted), so they can be restored even after a restart. Files you add there yourself are never deleted — if their folder goes away they're moved along, or put in the Trash.

## Right-click menu

On empty board space: **New Note** (⌘1), **New Folder** (⌘2), **New ▸** (Linker, PhotoBook, Notepad, Files, styled folders),
**View ▸** (Icons / List), **Arrange By ▸** (None, Name, Kind, Date Added, Tags), **Clean Up** (the wand), **Deep Clean Up…** (Settings),
**Paste**, and **Show in Finder** (opens this folder in Documents).

## Tags and renaming several things

- Right-click → **Tags** for the seven Mac colors (on one thing or a whole selection). The dots show next to names, and
  they're real Finder tags on the files in Documents.
- Select several things → right-click → **Rename N Items…**: a name and a starting number ("Poster 1, Poster 2…"), with a preview.

## Dragging out

Dragging something out of Stash gives a copy of the real thing: a folder with everything inside, a note as its .txt/.rtf,
a link as a little readable note (.rtf: its title and the clickable link), pictures and files as themselves.
Dropped into a text box instead (Messages, Notes, a browser), a note pastes its words and a link pastes the link. Stash's own copy stays put.

## Moving things around (Arrange By)

In Icons view you can drag any card or folder anywhere on the board and it stays there (Finder's "None").
It moves with the pointer the moment you press and drag — no need to select it first. Drag it over a folder to put it inside,
or out of the window to give another app a copy. Press, hold and let go without moving to rename.
Dragging one of several selected things moves them all. New things take the first free spot, and folder numbers (1–9) follow
where the folders sit, reading left to right. The compact preview and the big window each keep their own arrangement.
The **Arrange By** button at the top (or right-click → Arrange By) lines everything up again by **Name**, **Kind**, **Date Added**
or **Tags**. Dragging something afterwards switches back to None. ⌘Z undoes a move or an arrange.

## Quotes, Space and ⌘C

- **Space** on a selected note opens it for editing (like double-clicking); on a picture it shows the big preview.
- **⌘C** copies what's selected — a note's text, a link, a picture or file (several notes and links paste one after another).
  The copy buttons work on the very first click, even before Stash's window is in front.
- Big window: the **❝ quotes button** shows every note as a quote — its whole text, when you saved it, and a **Copy** button —
  so something you pasted long ago is easy to find, read and copy again. Click it again for note icons.

## Draw the window's frame

Big window: click the **dashed-rectangle button** and the screen dims — drag a box where you want Stash to sit and it snaps to exactly
that frame and locks there (no resizing at the edges, no moving), even after you close and reopen it. Click it again to draw a new
frame; hold it for **Unlock Frame**. Esc cancels drawing. The smallest frame is 460 × 380.

## Latest additions

- Things you drag out are fresh copies made just for that drop (instant on the same disk), never the library's own files —
  iCloud keeps everything inside the hidden library folder flagged "hidden", and handing those out made copies arrive invisible.
- **Drag anything out** (to the Desktop, Finder, another app) and it arrives as a real Mac file: folders with everything inside,
  notes as .txt/.rtf, links as a little TextEdit note, pictures, MP3s and MP4s as themselves. Drag a **project tab** out for a copy
  of the whole project as a folder.
- **Space** opens the real macOS **Quick Look** for pictures, videos, music and files (Space or Esc closes it; notes still open for editing).
- **Save to Mac…** (right-click a project tab, or Not Selected): pick a place and Stash makes a real folder there and keeps it up to
  date as you change things. It only touches what it put there — your own files in that folder stay — and removed things go to the
  Trash. Right-click again for **Show Saved Copy in Finder** or **Stop Updating Saved Copy**.
- **The pop-up** is a bit smaller and shows everything as small icon tiles with names: pictures as thumbnails, files with their own Mac
  icons, links with their preview and a link badge, YouTube links and media files with **MP3 / MP4** buttons.
- **Big window ❝ button**: off = the same minimal tiles; on = everything in full (notes as quotes, link previews, file details).
  Each mode keeps its own arrangement.
- **Downloads** show their progress right on the link. When the MP3/MP4 is ready it takes the link's place, and the link lives inside
  it as a small badge on its top-left — click it to open, copy, put back on the board or remove the link. No extra copies, no prompt.
- **Folder look ("Dot")**: every folder is the same quiet gray shape; a small colored dot in its corner says what kind it is —
  blue folder, green Linker, coral PhotoBook, amber Notepad, gray Files (Kraft, Pastel and Midnight get their own dots).
- **Folders show how full they are**: empty stays flat, 1–5 things shows a sheet peeking out, more shows a stack, with a small count
  (20+ after twenty).
- **Search** looks only in the tab you're on (the project, or Not Selected) and finds folders and things by name, anywhere inside.
- The **frame button** (dashed rectangle ▾) is optional: **Draw Frame…**, **Lock** or **Unlock** — click or right-click. When locked it
  turns into an orange **🔒 Locked**, and stays put until you unlock.

## Projects, tabs and night mode

- The top of both windows is now two rows, like a browser: the **project tabs** on their own strip, the tools underneath.
- Tabs show only the projects you're working on: the **pinned** ones (📌) and the ones you opened last — as many as fit,
  always including the one you're in. Right-click a tab → **Pin Tab / Unpin Tab**.
- The **▾ 7** button next to the tabs opens a simple list of every project (with how many things are in each and a pin).
  Click one to open it; it gets a tab. **New Project** is at the bottom.
- **Icons | List**: a two-part switch like Finder's, the current view highlighted.
- **Day and night by the clock**: Stash turns dark at 7 pm and light again at 7 am, by itself — nothing to switch.
- **Settings → Toolbar**: turn each header tool on or off (Search, Recent copies, Lock / Unlock, ❝ view, Arrange By, Icons | List,
  Organize wand). Their shortcuts keep working either way.
- **Search** only takes your typing after you click it (or press ⌘F); click anywhere else and typing stops going there.

## Recent copies

The **clipboard button** (📋) in the toolbar keeps the **last 5 things you copied anywhere on your Mac** — text, links,
files and pictures. Click one to copy it again, hover for **Save to** (the board you're on) or **×** to remove it,
or drag it out. Copied files aren't duplicated: only a link to the original is kept, so they take no space (if the
original is moved or deleted it says so). Pictures keep a small preview (a few dozen KB). Anything a password manager
marks as secret is never kept. Turn the button off in Settings → Toolbar if you don't want it.

## Safety: Recently Deleted, crash-safe saving, test app

- **Recently Deleted** (right-click the board, or right-click 🗑 Clear): everything you delete stays recoverable for
  **30 days — even after Stash restarts**. Click **Restore** to put it back where it was (if its folder or project is gone,
  it comes back on the board), × to delete one for good, or **Empty**. Files wait in `.stash/trash`; the list is
  `.stash/trash/deleted.json`. Things removed by ⌘Z/⌘⇧Z land there too.
- **Crash-safe saving**: saves are written in the background (typing and dragging never wait), checked by reading them
  back, then swapped in at once. The version before is kept as `.stash/library.prev.json`, and about once an hour a copy goes
  to `.stash/backups` (newest 24 kept). If `library.json` is ever damaged, Stash opens the last good version, keeps the
  damaged file aside (`library-unreadable-….json`) and tells you — it never starts empty over your library.
- **Stash Test** (`./build.sh test` → `build/Stash Test.app`): a separate app for testing, with its own settings, its own
  library (`~/Library/Application Support/Stash Test/Library`), its own `stashtest://` links and no global shortcuts.
  It can run next to the real Stash without touching it. Test hooks (`stashtest://debug…`) only work in Stash Test.

## Speed

- **Dragging** is Finder-style: when a drag starts, Stash takes a picture of the dragged tiles and moves that on its own
  layer; the real tiles stay dimmed in place until you let go. A mouse move no longer redraws the board:
  ~450 ms per step and 80,046 card redraws before → 16.7 ms per frame (smooth 60 fps), 0 redraws per frame.
- **The mirror** (the real files in Documents) remembers what it last wrote for each thing and only touches what changed:
  one change took 207–280 ms on the main thread → ~35 ms. Every file is still checked at launch and every 5 minutes,
  which catches files changed or removed outside Stash.
- Timing is recorded only in **Stash Test** (`perf …` lines on its stderr); the real Stash pays nothing for it.

### Big libraries (measured on a 10,000-item test library: 200 folders, 1,000 things loose on one board)

Before, Stash Test froze for minutes on this library and then crashed (SwiftUI ran out of room for views). Now:

| | Before | Now |
|---|---|---|
| First look at the board | froze > 3 min | ~3 s |
| Memory | 1.3–2.7 GB, then crash | 130–220 MB |
| Any change (a click, a selection) | many seconds | ~80 ms of main-thread work |
| Open a folder / back to the board | seconds | ~0.2 s |
| Switch project tab | seconds | 0.14–0.18 s |
| Search, per search run | up to 46 s | 0.23–0.3 s (and it runs once you pause typing, not on every key) |
| Folder counts (150 folders) | 66–107 ms per redraw | 0.05 ms |

What changed:
- **Only what's on screen is made.** With small tiles, every place on the board is worked out first (cheap), and only the
  tiles on screen — plus a little margin — become real views. Scroll, and tiles come and go. Tiles have a fixed height
  (names always get room for two lines, like Finder's icon grid), which is what makes this possible.
- **Free spots are found fast.** Placing new things around ones you moved by hand used to check every tile against every
  other (billions of checks on a big board); now each search picks up where the last one ended and only looks at neighbours.
- **Hidden windows stop drawing.** The pop-up, the window and the floating frame each had a live board; now only the one
  on screen follows changes.
- **Counts and lists are remembered** (folder fullness, project and tag counts, the board's contents, search text) until
  something in the library actually changes.
- **Saves that change no files skip the mirror**: switching tabs, moving tiles, Arrange By and pins no longer re-check
  the whole mirror in Documents.
- **Search waits for a pause** (0.15 s) while you type.

Still the old way (slower on huge boards): the big window's full-card view (❝) and List view.

## Big files (4K/8K video, RAW photos, project files, 10–50 GB)

Tested with a 20 GB and a 40 GB file, a 100-megapixel picture and 150 MB archives on a separate (ejectable) drive.

- **Big files are linked, not copied.** Files over the limit (Settings → Big files; 250 MB by default, or 100 MB / 1 GB /
  5 GB / no limit) stay where they are: the card and its folder in Documents point at the original. Adding a 20 GB video
  takes no time and no space. A small arrow on the card means "linked". Copies already in Stash stay copies.
- **Moved, renamed or on a drive that's not connected**: the card gets an orange **?** right away (Stash notices drives
  coming and going) — click it for **Find Original…**. A renamed or moved original is found again by itself (bookmark),
  and its link in Documents follows. Stash never moves, renames or deletes an original; deleting the card removes only the link.
- **Keep a Copy in Stash** (right-click a linked file) makes a real copy, for when the drive won't always be there.
- **Copies are safe**: in the background, two at a time, with a progress ring and a Cancel button on the card. Written
  under a temporary name and only renamed into place when complete; checked for free space first ("Not enough space…
  kept as a link"). Same disk → an instant APFS clone; another disk → streamed, never read into memory. Cancelled or
  failed → the card keeps a link to the original. Leftovers from an interrupted copy are cleaned at the next launch.
- **Pictures** are cloned in off the main thread (never read into memory); huge ones over the limit are linked.
  Text recognition runs one at a time, and is skipped for pictures over 50 megapixels.
- **Thumbnails** are made in the background (two at a time) at the size they're shown — 256 px for tiles, 900 px for
  big cards — with ImageIO (camera RAW files use their built-in preview when it's big enough). Placeholders show
  meanwhile; nothing waits. ⌘C on a picture over 40 megapixels copies the file instead of decoding it.
- **Dragging out is instant**: a linked file hands over the original (the other app copies it — only copy, never move);
  Stash's own files hand over a clone made when the drop happens, not when the drag starts (< 1 ms measured).
- **Conversions**: one at a time. Video → MP4 is **rewrapped** when it's already H.264/HEVC + AAC (seconds, no quality
  lost; re-encoded only otherwise). → MP3 streams the sound straight into the encoder (no huge temporary WAV). Both check
  free space first, and a conversion that stops making progress for 30 s gives up instead of hanging. Fixed: sound →
  MP4 used to hang, and made the video twice as long as the sound.
- **Settings → Storage** shows linked files separately ("not stored by Stash", not counted in the total), with how many
  aren't found right now.

## Disk space

- **Previews are small**: link pictures and file/video thumbnails are kept at most 600 px, as JPEG (PNG only when they have
  see-through parts). Older big previews are shrunk once, automatically (a 3.3 MB test preview became 103 KB). Your own
  pictures and files are never touched.
- **The downloader isn't stored twice any more**: yt-dlp runs from inside Stash; a separate copy is made only when you
  update it in Settings. The old identical 35 MB copy in Application Support is removed.
- **Backups are compressed** (about 8× smaller — a 600 KB library backup takes 76 KB) and still restore automatically.
- **Temporary copies** (drags, Quick Look, link notes) are removed at every launch.
- **The picture cache in memory** has a limit (500 pictures / 200 MB), so a big board can't keep growing in memory.
- **Settings → Storage** shows what Stash uses — your files, previews, Recently Deleted, library and backups,
  recent copies, temporary files, built-in tools — with **Clear Temporary Files**, **Empty Recently Deleted…**,
  **Show in Finder**, and **Move to Trash** for the old library from an earlier Stash version (if it's still there).

## Clear feedback and accessibility

- **Where things go**: the tool row always shows **↓ Project ▸ Folder** — where pasted, dropped and quick-saved things land.
- **Undo right in the message**: after deleting, moving, renaming, clearing, organizing, restoring or a finished download,
  the message at the bottom has an **Undo** button (it stays 4 seconds).
- **Downloads and conversions**: the progress ring on the link or file has a small **×** to cancel. If one doesn't work,
  a red **!** stays on it — click it to see why, **Try Again** or **Dismiss** (no more messages that vanish).
- **VoiceOver**: every icon-only button has a spoken name; cards and folders read as "Note: …", "Linker folder: …, 12 things
  inside", with Open as an action; messages are read out.
- **Reduce motion** (System Settings → Accessibility) turns off Stash's sliding and springing animations.

## Recent (Stash 2.0, phase 1)

- **Recent** is the first tab: a temporary inbox of what you copied and screenshotted lately, newest first — text,
  links, pictures, files and screenshots, each with where it came from, when, and ×N if you copied it again.
- **Capture is off until you turn it on** (the card in Recent, or Settings → Capture): *Capture what I copy* and
  *Capture screenshots* (only real screenshots, only in the folder you choose — by default where macOS saves them).
- **Keep** (the button, Return or ⌘K) makes it permanent in the project/folder you were in before opening Recent; its ▾
  picks another project. Copied files and screenshots are only *linked* in Recent and copied into the project only when
  you Keep them. The entry stays in Recent, marked "✓ Kept in …", until it expires.
- **Pause** any time: the Capturing/Paused switch in Recent, Settings → Capture, or right-click the menu bar icon.
- **Limits**: Recent keeps things for 1 day, 7 days (default), 30 days or until you clear it, and up to 100 MB – 1 GB
  (500 MB default) — the oldest go first. *Never capture from* lists password managers by default; add any app.
- Keys in Recent: ↑↓ move, Space looks, Return/⌘K keeps, ⌘⌫ removes, ⌘C copies again, ⌘A selects all; drag rows out.
- The old *Recent copies* list (last 5) moved into Recent.

## Stash 2.0, phase 2: simpler pop-up, sidebar, shortcuts

- **Simpler pop-up**: still two rows (tabs, then tools), but the tool row is just **↓ where things go**, the **🔓 lock**
  (always visible), **···** and expand. **···** holds Arrange By, View (icons/list), Organize Into Folders,
  Recently Deleted, Show in Finder and Settings. The bottom bar is **+ New ▾** (note, folder, Linker, PhotoBook, Notepad,
  Files — ⌘1–⌘6 still work), Clear and ?. Recent shows as a clock icon in the pop-up's tabs.
- **Sidebar in the big window**, like Finder: **Recent**, **All Items**, **Projects** (Not Selected, pinned first, then
  most recent; + for a new one; right-click to pin, rename, save to Mac or delete) and **Tags** (the colours you use).
  The sidebar button (⌸) in the tool row hides it — the project tabs then come back.
- **All Items**: every thing in every project, newest first, with **All · Links · Pictures · Notes · Files** filters,
  where each one lives, and ➜ to jump to it in its project. Search covers everything here. A **tag** in the sidebar
  shows everything with that colour, folders included.
- **Settings → Shortcuts**: click a shortcut and press the keys you want — **Open or close Stash** (⌥Space), **Save the
  clipboard without opening Stash** (⌥⌘V) and **Keep** in Recent (⌘K). Esc cancels, ⌫ turns a global one off, ↺ resets.
  Stash refuses keys macOS uses (⌘Space, ⌘Tab, ⌘Q…), a key without ⌘/⌥/⌃ for global shortcuts, and duplicates, and warns
  when another app already owns the shortcut.

## Projects only, Recent links, three window modes, Connected Folders

- **No more Not Selected**: just **Recent** and your **Projects**. Things that had no project moved into **Unsorted**
  (rename it as you like); there's always at least one project.
- **One copy, two places**: anything you save into a project also shows in **Recent** — as the same thing, not a copy
  ("In Poster Series ▸ PhotoBook", with ➜ to jump there). **Keep** turns a Recent capture into a project item and deletes
  Recent's own copy, so nothing is stored twice. Removing it from Recent leaves it in its project.
- **Screenshots**: the Recent header now has two switches, **📋 Copies** and **📷 Screenshots** — both on with
  *Turn On Capture*. Turning screenshots on also picks up the ones from the last 10 minutes.
- **⌥1–⌥9**: with things selected (or while dragging them), ⌥ + a folder's number puts them into that folder.
- **Three modes, one window at a time** (Stash reopens in the one you used last):
  - **Pop-up** from the menu bar (lock it to keep it in one place),
  - **Window** — the full window with the sidebar,
  - **Float** — a frame that stays above every app and Space: move it by its top, resize it from its edges, zoom with
    − / + or ⌘− / ⌘+ / ⌘0 (60–160 %). Get there from ··· → *Float on Top of Every App* or the ▭ button in the window.
- **Connected Folders** (view only): the sidebar's **Connected** section (+, or drop a folder on its heading), or ···
  → Connected Folders in the pop-up and floating frame. Browse subfolders, filter names, Space for Quick Look,
  double-click to open, drag out for a copy, Reveal in Finder. Finder changes show up by themselves; a moved folder is
  followed; a missing one shows *Folder unavailable* with Locate… / Remove Shortcut. Nothing is copied into Stash and
  nothing in the folder is ever changed — removing the shortcut leaves the folder exactly as it is.

## Get Info

**⌘I** or right-click → **Get Info** opens a small Info window, like Finder's: name, size (and how many things a folder holds), kind,
where it is, the link, picture or video dimensions, duration, when it was added and last modified, colour tags you can click,
**Show in Finder** and a preview. Select several things to get one window for each (up to five).

## Clear

The **🗑 Clear** button in the bottom bar empties the tab you're on — the project, or Not Selected — folders with everything
inside them, and loose things. The first click turns it into a red **Clear all?**; click again within 3 seconds to clear.
Other projects aren't touched, and **⌘Z** brings it all back.

## Keys for deleting and going back

**⌘⌫** deletes what's selected straight away, no questions — a folder goes with everything inside (⌘Z brings it back). **⌫** or **Tab** goes back up to the folder holding this one.

## Renaming

Like Finder: select something and press **Return**, click the name of a selected folder, or long-press. Return saves, Esc cancels, and clicking anywhere outside the name box saves it.
Double-click (or ⌘↓) opens. Renaming a picture or file renames the real file in Documents too.
New folders open their name box straight away with a plain numbered name (Folder, PhotoBook 2…) selected — type a name, or press Return to keep it.

## Notes

**Return** saves a note, **Shift+Return** goes down a line (the ✓ button saves too). New Note (⌘1) and Edit have a toolbar: **Aa** font (every font on your Mac) and size, **B I U**, line spacing (1.0–2.5),
color, **🙂 emoji** (a quick grid, or the Mac's full picker with ⌃⌘Space), and **– • 1.** lists (Return continues the list, Return on an empty item ends it).

## Convert and download as MP3 / MP4

- Click the **MP3** / **MP4** chips on a video or sound **file** to convert it, or on a **media link**
  (YouTube, Vimeo, SoundCloud, TikTok, Instagram, X… or a direct link to a media file) to download it.
  Ordinary web links don't get the chips. The same options are in the right-click menu.
- While it's being made, a see-through placeholder card (or row, in List view) shows the progress.
  After a link download, Stash asks whether to delete the link.
- Results are saved next to the original, in the same folder. Only download things you have the right to.

Needs FFmpeg and yt-dlp (free), installed once in Terminal — Stash shows these lines if they're missing:

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew install ffmpeg yt-dlp

## Quick save, files, pin

- Copy anything (a file in Finder, an image, a link, text) and press **⌥⌘V** from any app: it's saved without opening Stash —
  into the project tab you last had open (or Not Selected), inside its **Files** / PhotoBook / Linker / Notepad folder if there is one.
  Dropping onto the menu bar icon works the same way. Change or turn off the shortcut in Settings (⌥⌘V is also Finder's "move here").
- Videos, music, 3D models and other files are **copied into Stash**, so they stay even if you delete the original (turn off in Settings).
- **Lock / Unlock** (the 🔓 ▾ button): drag the small pop-up anywhere by its top bar, then **Lock** — it stays exactly there and reopens there until you **Unlock** (then it hangs under the menu bar icon again). In the big window the same button has **Draw Frame…**, **Lock** and **Unlock**; while the big window is locked, Stash reopens big. (This replaces the old 📌 pin.)
- **Tabs** at the top are your projects: click to switch, double-click to rename, **×** to delete (it asks if there's anything inside), **+** adds a new tab right there with its name box open — type a name and press Return (or click away).
- **Icons ⇄ List** button in the header switches how the board and folders are shown.
- Drag cards **or folders** onto a folder to put them inside; drag them onto the **←** arrow or any part of the path to take them out.
- Inside a folder, the 🗑 at the top right deletes the folder you're in.

## Number keys and the bottom bar

| Keys | Does |
|---|---|
| **⌘1** | New Note |
| **⌘2** | New Folder |
| **⌘3** · **⌘4** · **⌘5** · **⌘6** | New **Linker** · **PhotoBook** · **Notepad** · **Files** folder |
| **1 – 9** | Open the folder with that number on the board (each folder shows its number) |
| **⌃Tab** / **⌃⇧Tab** | Next / previous project tab |

New folders are made inside the folder you're in. The same six are buttons along the bottom of the window and at the
top of the right-click menu. The **?** at the bottom right lists what every button, key and click does.

## Getting things in

| How | What happens |
|---|---|
| Click the **menu bar icon** or **⌥Space** | Opens / closes a small preview under the icon (Esc also closes it) |
| **⤢** in the preview | Expands into a big window you can move and resize; **⤡** shrinks it back |
| Drag onto the **preview or window** | Saves to the selected project |
| Drag onto the **menu bar icon** | Saves without opening anything (icon flashes ✓) |
| **⌘V** in the panel | Saves the clipboard — image, link, file or text |
| **Right-click** the board → New Note (⌘N) | Write a note. `#tags` are picked up automatically |
| Right-click menu bar icon → Save Clipboard | Same as ⌘V without opening the panel |
| Take a screenshot, then **⌥Space** | Saves it to the project that's open (or Not Selected) |
| Copy anything, then **⌥Space** | Opens the folder for it (link → Linker, image → PhotoBook, text → Notepad, file → Files) with a **Paste ⌘V** banner. If there's no folder of that kind here, it's saved on the page (Settings can make it create the folder instead) |
| `open "stash://clipboard"` / `stash://add?text=…` | For Shortcuts, Raycast, scripts |

- **Links** get their page title and preview image.
- **Images** are copied into the library and their text is read (OCR), so you can search for words *inside* images.
- **Other files** (videos, PDFs, folders) are saved as references with a Quick Look thumbnail.

## Folders

- Folders show **just their icon**. Right-click → **Name…** to give one a name (shown under it); **Remove Name** goes back to the icon.
- **Folders can go inside folders.** Anything you create while inside a folder (1–5, right-click, styled folders) is made inside it.
  ← (⌘[) goes up one level; the path at the top shows where you are — click any part to jump there.
- The **wand** organizes the folder you're in. Inside a Linker/PhotoBook/Notepad, things that don't belong move to the right kind of folder next to it.
- **Settings (⌘, or right-click the menu bar icon)**: what the wand organizes, whether to ask about existing folders, and
  **Deep Organize** — goes through every folder at every level and puts everything in the right kind of folder (undo with ⌘Z).

- Right-click the board → **New Folder** (⌘⇧N), or **New Styled Folder** → Kraft, Pastel, Midnight, Linker, PhotoBook, Notepad, Files.
- Click a folder to open it, **Back** (⌘[ or **Tab**) to go up to the folder holding it. Things you drop or paste while it's open go inside.
- Drag cards onto a folder to put them in; drag things from other apps straight onto a folder too.
- Right-click a folder to rename it, change its style or delete it (it goes with everything inside).
- The **✨ wand** button organizes everything loose automatically: links → **Linker**, photos → **PhotoBook**,
  notes → **Notepad**, files → **Files**. If those folders already exist it asks: add to them, or make new ones (PhotoBook 2…).

## Using them

- Tabs at the top: **Not Selected** (things in no project) and your projects (**+** to add, right-click to rename/delete).
  ⌘1 = Not Selected, ⌘2… = projects. ⌘F = search, ⌘N = new note.

## Selecting

- Click to select, **⌘-click** to add/remove, **shift-click** for a range, **⌘A** for everything.
- **Drag a box** on empty space to select what it touches (hold ⌘ or shift to add).
- **Arrow keys** move the selection (shift+arrow extends it). **⌘⌫** deletes, **Return** renames, **⌘↓** opens, **Esc** deselects.
- Right-click a selection to **Move to Project**, **Put in Folder** or **Delete** all of it at once.
- Drag one of several selected cards onto a folder to move them all.
- (On a Mac, ctrl-click is right-click.)

## Notebook (set aside)

The handwriting notebook is taken out for now. Its code is kept in `Unused/Notebook.swift.txt`, and pages you wrote
are still in the library, so it can come back.

## Undo

- **⌘Z** (or **Ctrl Z**) undoes the last change — deletes, moves, organizing, new folders, renames, pastes.
  **⌘⇧Z** redoes. Deleted images can be brought back until Stash restarts.

## Previewing images

- Double-click an image, press **Space**, or right-click → **Preview** to see it big.
- In the preview: ← → for the next image, **Open** (↩) opens it in your image app, Space/Esc closes.
- **Drag cards out** into Figma, Finder, mail, etc.
- Double-click to open; hover for open/copy/delete; right-click to move, add a note, open the source page.
- Click a `#tag` to filter by it.

## Data

Everything lives in `~/Library/Application Support/Stash/` (`library.json` + `images/`).
Right-click the menu bar icon → *Show Library in Finder*.

## Code map

- `AppDelegate.swift` — menu bar icon, hotkey, panel, menus, URL scheme
- `Panel.swift` — floating window, ⌘V handling, drop target
- `Store.swift` — library state and persistence
- `Ingest.swift` — turning drops/pastes into items, link previews, OCR, thumbnails, drag-out
- `Views/` — SwiftUI board, cards, project tabs, masonry layout
