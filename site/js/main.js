import { setupClips } from "./videos.js";
import { resolveRelease } from "./release.js";
import { checkoutLink, PRICE } from "./purchase.js";

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

/* Header: border once scrolled, mobile menu, current section in the nav. */
function setupHeader() {
  const header = $(".nav-bar");
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
setupClips();
setupSound();
setupReveal();
setupDownload();
