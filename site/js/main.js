import { setupClips } from "./videos.js";
import { resolveRelease } from "./release.js";
import { checkoutLink, PRICE } from "./purchase.js";
import { setupWand } from "./wand.js";

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

/* Header: white over the film, solid after it; mobile menu; current section in the nav. */
function setupHeader() {
  const header = $(".nav-bar"), hero = $(".hero");
  const onScroll = () => header.classList.toggle("is-scrolled", !hero || scrollY > hero.offsetHeight - header.offsetHeight);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  const toggle = $(".menu-toggle"), links = $("#nav-links");
  const close = (focusToggle) => {
    links.classList.remove("is-open");
    toggle.setAttribute("aria-expanded", "false");
    toggle.textContent = "Menu";
    header.classList.remove("is-solid");
    if (focusToggle) toggle.focus();
  };
  toggle.addEventListener("click", () => {
    const open = toggle.getAttribute("aria-expanded") !== "true";
    links.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
    toggle.textContent = open ? "Close" : "Menu";
    header.classList.toggle("is-solid", open);
    if (open) links.querySelector("a")?.focus();
  });
  links.addEventListener("click", e => { if (e.target.closest("a")) close(false); });
  document.addEventListener("keydown", e => { if (e.key === "Escape" && links.classList.contains("is-open")) close(true); });
  document.addEventListener("click", e => { if (links.classList.contains("is-open") && !e.target.closest(".nav")) close(false); });
  matchMedia("(min-width: 48em)").addEventListener?.("change", e => { if (e.matches) close(false); });

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

/* The hero film: muted until the visitor asks for sound. */
function setupSound() {
  const fig = $("#film"), btn = fig && $(".sound-btn", fig);
  if (!btn) return;
  const video = $("video", fig);
  btn.addEventListener("click", () => {
    const on = video.muted;
    video.muted = !on;
    fig.dataset.sound = on ? "on" : "off";
    btn.setAttribute("aria-pressed", String(on));
    $(".label", btn).textContent = on ? "Sound on" : "Sound";
    if (on && video.paused) $(".play-btn", fig)?.click(); // a click is a user gesture: sound may start
  });
}

/* Tabs (WAI-ARIA pattern): each switches its panel, and a picture when one is marked for it. */
function setupTabs() {
  for (const list of $$("[role='tablist']")) {
    const tabs = $$("[role='tab']", list);
    const section = list.closest("section");
    const select = (tab, focus) => {
      for (const t of tabs) {
        const on = t === tab;
        t.setAttribute("aria-selected", String(on));
        t.tabIndex = on ? 0 : -1;
        document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
      }
      const pics = $$("[data-for]", section);
      if (pics.some(p => p.dataset.for === tab.id)) pics.forEach(p => { p.hidden = p.dataset.for !== tab.id; });
      if (focus) tab.focus();
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

/* The small blades: pointing at (or focusing) a name shows what it does in the empty columns. */
function setupIndex() {
  const note = $("[data-index-note]");
  if (!note) return;
  const show = li => { note.textContent = li.dataset.note; };
  for (const li of $$("[data-index] li[data-note]")) {
    li.addEventListener("mouseenter", () => show(li));
    li.addEventListener("focus", () => show(li));
  }
}

/* Phones held upright get the vertical cut of the film. */
function chooseFilm() {
  const video = $("#film video");
  if (!video || !matchMedia("(max-width: 47.9375em) and (orientation: portrait)").matches) return;
  const source = $("source", video);
  source.src = video.dataset.tallSrc;
  video.poster = video.dataset.tallPoster;
  video.load();
}

/* Download: show a real release if GitHub has one; otherwise the honest "build it" path. */
async function setupDownload() {
  const status = $("#release-status");
  if (!status) return;
  // Selling: a valid Lemon Squeezy checkout link turns on the Buy button (purchase.js). No link, no button.
  const buy = checkoutLink();
  if (buy) {
    $$("[data-price]").forEach(el => { el.textContent = PRICE; });
    $("[data-buy-link]").href = buy;
    $("#download-buy").hidden = false;
    $("#download-none").hidden = true;
    status.dataset.status = "ready";
    $("[data-release-text]").textContent = `Swiss 1.0 is available for ${PRICE}.`;
    $$("[data-download-cta]").forEach(a => { a.textContent = `Buy · ${PRICE}`; });
    return;
  }
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
chooseFilm();
setupClips();
setupTabs();
setupIndex();
setupWand();
setupSound();
setupReveal();
setupDownload();
