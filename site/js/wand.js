// The live board: add your own things, then wave the wand. It sorts by kind, the way Swiss's wand does:
// links into Linker, pictures into PhotoBook, notes into Notepad, everything else into Files.
// Nothing leaves the page: no network, no storage.

const PICTURE = /\.(jpe?g|png|gif|heic|webp|tiff?|bmp|svg)$/i;
const FILE = /\.[a-z0-9]{2,5}$/i;

export const FOLDERS = [
  { kind: "picture", name: "PhotoBook" },
  { kind: "link", name: "Linker" },
  { kind: "note", name: "Notepad" },
  { kind: "file", name: "Files" },
];

/** What a piece of text is, by kind only: "link", "picture", "file" or "note". */
export function kindOf(text) {
  const t = String(text ?? "").trim();
  if (!t) return null;
  if (/^(https?:\/\/|www\.)\S+$/i.test(t)) return PICTURE.test(t.split(/[?#]/)[0]) ? "picture" : "link";
  const looksLikeName = /^[^\n]{1,120}$/.test(t) && !/[.!?]\s/.test(t) && t.split(/\s+/).length <= 6;
  if (looksLikeName && PICTURE.test(t)) return "picture";
  if (looksLikeName && FILE.test(t)) return "file";
  return "note";
}

/** Groups items into the four folders, in their order, keeping only folders that get something. */
export function organize(items) {
  return FOLDERS.map(f => ({ ...f, items: items.filter(i => i.kind === f.kind) })).filter(f => f.items.length);
}

const LABEL = { link: "Link", picture: "Picture", note: "Note", file: "File" };
const MARK = { link: "L", picture: "P", note: "N", file: "F" };

export function setupWand(root = document) {
  const board = root.querySelector("[data-wand-board]");
  if (!board) return;
  const list = board.querySelector(".cards"), folders = board.querySelector(".folders");
  const form = board.querySelector("form"), input = form.querySelector("input");
  const wand = board.querySelector(".board-wand"), toast = board.querySelector(".board-toast");
  const live = board.querySelector("[data-wand-live]");
  // Start from the example cards already in the markup (they're the no-script view too).
  let items = [...list.querySelectorAll(".card")].map(li => ({ text: li.dataset.text, kind: li.dataset.kind }));
  let sorted = false;

  const card = (item, fresh) => {
    const li = document.createElement("li");
    li.className = "card" + (fresh ? " is-new" : "");
    li.dataset.kind = item.kind;
    const mark = document.createElement("span"); mark.className = "kind"; mark.setAttribute("aria-hidden", "true"); mark.textContent = MARK[item.kind];
    const body = document.createElement("div"); body.textContent = item.text;
    const small = document.createElement("small"); small.textContent = LABEL[item.kind]; body.append(small);
    li.append(mark, body);
    return li;
  };
  const showCards = () => {
    sorted = false;
    folders.hidden = true; toast.hidden = true; list.hidden = false;
    wand.setAttribute("aria-pressed", "false");
  };
  const showFolders = () => {
    sorted = true;
    folders.replaceChildren(...organize(items).map(f => {
      const li = document.createElement("li"); li.className = "folder is-new"; li.dataset.kind = f.kind;
      const h = document.createElement("h4"); h.textContent = f.name;
      const n = document.createElement("span"); n.textContent = f.items.length; h.append(n);
      const ul = document.createElement("ul");
      ul.append(...f.items.map(i => { const x = document.createElement("li"); x.textContent = i.text; return x; }));
      li.append(h, ul); return li;
    }));
    const groups = organize(items).length;
    toast.textContent = `Organized ${items.length} items into ${groups} folder${groups === 1 ? "" : "s"}`;
    list.hidden = true; folders.hidden = false; toast.hidden = false;
    wand.setAttribute("aria-pressed", "true");
    live.textContent = toast.textContent;
  };

  form.addEventListener("submit", e => {
    e.preventDefault();
    const text = input.value.trim().slice(0, 140);
    const kind = kindOf(text);
    if (!kind) { input.focus(); return; }
    items = [{ text, kind }, ...items].slice(0, 12);
    if (sorted) showCards();
    list.prepend(card(items[0], true));
    while (list.children.length > items.length) list.lastElementChild.remove();
    live.textContent = `Added a ${LABEL[kind].toLowerCase()}: ${text}`;
    input.value = "";
  });
  wand.addEventListener("click", () => (sorted ? showCards() : showFolders()));
}
