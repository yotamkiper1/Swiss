import { setupClips } from "./videos.js";
import { resolveRelease } from "./release.js";

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

/* Header: border once scrolled, mobile menu, current section in the nav. */
function setupHeader() {
  const header = $(".site-header");
  const onScroll = () => header.classList.toggle("is-scrolled", scrollY > 8);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  const toggle = $(".menu-toggle"), links = $("#nav-links");
  const close = (focusToggle) => {
    links.classList.remove("is-open");
    toggle.setAttribute("aria-expanded", "false");
    toggle.setAttribute("aria-label", "Open menu");
    if (focusToggle) toggle.focus();
  };
  toggle.addEventListener("click", () => {
    const open = toggle.getAttribute("aria-expanded") !== "true";
    links.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
    toggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    if (open) links.querySelector("a")?.focus();
  });
  links.addEventListener("click", e => { if (e.target.closest("a")) close(false); });
  document.addEventListener("keydown", e => { if (e.key === "Escape" && links.classList.contains("is-open")) close(true); });
  document.addEventListener("click", e => { if (links.classList.contains("is-open") && !e.target.closest(".nav")) close(false); });
  matchMedia("(min-width: 47.5625em)").addEventListener?.("change", e => { if (e.matches) close(false); });

  if (!("IntersectionObserver" in window)) return;
  const navLinks = $$("#nav-links a[href^='#']");
  const targets = navLinks.map(a => document.getElementById(a.hash.slice(1))).filter(Boolean);
  const io = new IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      for (const a of navLinks) {
        if (a.hash === "#" + e.target.id) a.setAttribute("aria-current", "true");
        else a.removeAttribute("aria-current");
      }
    }
  }, { rootMargin: "-40% 0px -55% 0px" });
  targets.forEach(t => io.observe(t));
}

/* Organize: Projects / Magic wand tabs (WAI-ARIA tabs pattern). */
function setupTabs(clips) {
  for (const list of $$("[role='tablist']")) {
    const tabs = $$("[role='tab']", list);
    const select = (tab, focus) => {
      for (const t of tabs) {
        const on = t === tab, panel = document.getElementById(t.getAttribute("aria-controls"));
        t.setAttribute("aria-selected", String(on));
        t.tabIndex = on ? 0 : -1;
        panel.hidden = !on;
        $$(`[data-tab-copy="${panel.id}"]`).forEach(c => { c.hidden = !on; });
        const fig = panel.querySelector("[data-clip]");
        if (fig && !on) clips?.hide(fig);
      }
      if (focus) tab.focus();
      clips?.refresh();
    };
    tabs.forEach((t, i) => {
      t.addEventListener("click", () => select(t));
      t.addEventListener("keydown", e => {
        const step = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
        if (e.key === "Home") { e.preventDefault(); select(tabs[0], true); }
        else if (e.key === "End") { e.preventDefault(); select(tabs.at(-1), true); }
        else if (step) { e.preventDefault(); select(tabs[(i + step + tabs.length) % tabs.length], true); }
      });
    });
  }
}

/* The product film: a native <dialog>, sound only after the visitor presses play. */
function setupFilm(clips) {
  const dialog = $("#film-dialog");
  if (!dialog || typeof dialog.showModal !== "function") return; // links fall back to the MP4 itself
  const video = $("video", dialog);
  let opener = null;
  const sources = $$("source[data-src]", video), track = $("track[data-src]", video);

  video.addEventListener("error", () => dialog.classList.add("has-error"));
  sources.forEach(s => s.addEventListener("error", () => dialog.classList.add("has-error")));

  for (const btn of $$("[data-open-film]")) {
    btn.addEventListener("click", e => {
      e.preventDefault();
      opener = btn;
      if (sources.length && sources[0].dataset.src) {
        sources.forEach(s => { s.src = s.dataset.src; s.removeAttribute("data-src"); });
        if (track) { track.src = track.dataset.src; track.removeAttribute("data-src"); }
        video.load();
      }
      // Pause the silent clips while the film is open.
      $$("[data-clip] video").forEach(v => v.pause());
      dialog.showModal();
      const p = video.play(); // a click is a user gesture: sound is allowed and expected
      if (p && p.catch) p.catch(() => {});
      video.focus();
    });
  }
  const close = () => dialog.close();
  $(".close", dialog).addEventListener("click", close);
  dialog.addEventListener("click", e => { if (e.target === dialog) close(); }); // backdrop
  dialog.addEventListener("close", () => {
    video.pause();
    opener?.focus();
    clips?.refresh();
  });
}

/* Download: show a real release if GitHub has one; otherwise the honest "build it" path. */
async function setupDownload() {
  const status = $("#release-status");
  if (!status) return;
  status.dataset.status = "checking";
  const info = await resolveRelease();
  const ready = $("#download-ready"), none = $("#download-none");
  if (info.status === "ready") {
    $("[data-release-version]").textContent = info.version;
    $("[data-release-meta]").textContent = [info.file, info.size, info.date && `published ${info.date}`].filter(Boolean).join(" · ");
    const link = $("[data-release-link]");
    link.href = info.url;
    $("[data-release-page]").href = info.page;
    ready.hidden = false; none.hidden = true;
    status.dataset.status = "ready";
    $("[data-release-text]").textContent = `Swiss ${info.version} is available.`;
    $$("[data-download-cta]").forEach(a => { a.textContent = "Download for Mac"; });
  } else {
    status.dataset.status = "none";
    $("[data-release-text]").textContent = info.status === "error"
      ? "Couldn't reach GitHub to check for a release. Showing how to build Swiss."
      : "No signed release yet. You can build Swiss from its source today.";
  }
}

/* Gentle reveal for sections; everything is visible if this never runs. */
function setupReveal() {
  if (matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window)) return;
  const items = $$(".reveal");
  const io = new IntersectionObserver(entries => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add("is-in"); io.unobserve(e.target); }
  }, { rootMargin: "0px 0px -8% 0px" });
  // Only hide what's below the fold, so nothing on screen blinks.
  for (const el of items) {
    if (el.getBoundingClientRect().top > innerHeight) io.observe(el); else el.classList.add("is-in");
  }
  document.documentElement.classList.add("motion");
}

setupHeader();
const clips = setupClips();
setupTabs(clips);
setupFilm(clips);
setupReveal();
setupDownload();
