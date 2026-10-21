// Short, muted feature clips. At most one plays at a time: the most visible one,
// and only while the page is showing. A clip the visitor paused stays paused.
// With reduced motion nothing starts by itself; the play buttons still work.

/**
 * Which clip should be playing. Pure, so it can be tested.
 * clips: [{ id, ratio (0-1 visible), userPaused, userPlayed, failed }]
 */
export function chooseClip(clips, { hidden = false, reducedMotion = false, threshold = 0.5 } = {}) {
  if (hidden) return null;
  const eligible = clips.filter(c => !c.failed && !c.userPaused && c.ratio >= threshold && (!reducedMotion || c.userPlayed));
  if (!eligible.length) return null;
  // A clip the visitor started wins over autoplay; then the most visible; ties go to the first on the page.
  return eligible.reduce((best, c) => {
    if (c.userPlayed !== best.userPlayed) return c.userPlayed ? c : best;
    return c.ratio > best.ratio ? c : best;
  }).id;
}

export function setupClips(root = document) {
  const figures = [...root.querySelectorAll("[data-clip]")];
  if (!figures.length) return;
  const motionQuery = matchMedia("(prefers-reduced-motion: reduce)");
  const state = new Map();

  const label = (fig, text) => { const l = fig.querySelector(".media-control .label"); if (l) l.textContent = text; };
  const show = (fig, s) => {
    fig.dataset.state = s;
    const btn = fig.querySelector(".media-control");
    if (btn) btn.setAttribute("aria-pressed", s === "playing" ? "true" : "false");
    label(fig, s === "playing" ? "Pause" : "Play");
  };

  function update() {
    const list = figures.map(f => ({ id: f.id, ...state.get(f) }));
    const winner = chooseClip(list, { hidden: document.hidden, reducedMotion: motionQuery.matches });
    for (const fig of figures) {
      const s = state.get(fig), video = s.video;
      if (s.failed) continue;
      if (fig.id === winner) {
        if (!s.loaded) { load(fig); }
        const p = video.play();
        if (p && p.catch) p.catch(() => { s.userPaused = true; show(fig, "paused"); });
      } else if (!video.paused) {
        video.pause();
      }
    }
  }

  function load(fig) {
    const s = state.get(fig);
    s.loaded = true;
    const source = fig.querySelector("source[data-src]");
    if (source) { source.src = source.dataset.src; source.removeAttribute("data-src"); s.video.load(); }
  }

  for (const fig of figures) {
    const video = fig.querySelector("video");
    const s = { video, ratio: 0, userPaused: false, userPlayed: false, failed: false, loaded: false };
    state.set(fig, s);
    video.muted = true; // clips have no sound
    show(fig, "idle");
    video.addEventListener("playing", () => { fig.classList.remove("is-loading"); show(fig, "playing"); });
    video.addEventListener("pause", () => show(fig, "paused"));
    video.addEventListener("waiting", () => fig.classList.add("is-loading"));
    video.addEventListener("canplay", () => fig.classList.remove("is-loading"));
    const fail = () => { s.failed = true; fig.classList.remove("is-loading"); show(fig, "error"); update(); };
    video.addEventListener("error", fail);
    fig.querySelector("source")?.addEventListener("error", fail);
    fig.querySelector(".media-control")?.addEventListener("click", () => {
      if (video.paused) { s.userPaused = false; s.userPlayed = true; for (const [f, o] of state) if (f !== fig) o.userPlayed = false; }
      else { s.userPaused = true; s.userPlayed = false; }
      update();
    });
  }

  // Small screens: let the visitor see a clip full size.
  for (const fig of figures) {
    const s = state.get(fig), video = s.video;
    fig.querySelector(".media-expand")?.addEventListener("click", () => {
      if (!s.loaded) load(fig);
      s.userPaused = false; s.userPlayed = true;
      update();
      if (video.requestFullscreen) video.requestFullscreen().catch(() => {});
      else if (video.webkitEnterFullscreen) video.webkitEnterFullscreen(); // iPhone Safari
    });
  }

  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(entries => {
      for (const e of entries) {
        const s = state.get(e.target);
        s.ratio = e.isIntersecting ? e.intersectionRatio : 0;
        if (!e.isIntersecting) s.userPlayed = false; // leaving the screen ends "I chose this"
      }
      update();
    }, { threshold: [0, 0.25, 0.5, 0.75, 1] });
    figures.forEach(f => io.observe(f));
  }
  document.addEventListener("visibilitychange", update);
  motionQuery.addEventListener?.("change", update);

  // Lets the Organize tabs tell us a clip was hidden or shown.
  return { refresh: update, hide(fig) { const s = state.get(fig); if (s) { s.ratio = 0; s.video.pause(); } } };
}
