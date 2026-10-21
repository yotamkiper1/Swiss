// Finds a real, installable Swiss build on GitHub Releases. Nothing is assumed:
// no release, a draft, a pre-release or a release without a Mac build all mean "none".

export const REPO = "yotamkiper1/Swiss";
export const RELEASES_PAGE = `https://github.com/${REPO}/releases`;
export const LATEST_API = `https://api.github.com/repos/${REPO}/releases/latest`;

const INSTALLABLE = /\.(dmg|zip)$/i;
const NOT_FOR_USERS = /(source|src|debug|dsym|test)/i;

/** Picks the asset people should download from a GitHub "release" object, or null. */
export function pickAsset(release) {
  if (!release || release.draft || release.prerelease || !Array.isArray(release.assets)) return null;
  const candidates = release.assets.filter(a =>
    a && typeof a.name === "string" && typeof a.browser_download_url === "string" &&
    INSTALLABLE.test(a.name) && !NOT_FOR_USERS.test(a.name) &&
    a.state !== "starter" && a.browser_download_url.startsWith("https://github.com/"));
  // A disk image is the friendlier install; otherwise a zip.
  return candidates.find(a => /\.dmg$/i.test(a.name)) || candidates[0] || null;
}

export function formatSize(bytes) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "";
  const mb = bytes / 1_000_000;
  return mb >= 10 ? `${Math.round(mb)} MB` : `${mb.toFixed(1)} MB`;
}

/** Turns a release into what the page shows: { status: "ready" | "none", ... }. */
export function describeRelease(release) {
  const asset = pickAsset(release);
  if (!asset) return { status: "none", page: RELEASES_PAGE };
  const version = String(release.tag_name || release.name || "").replace(/^v/i, "");
  return {
    status: "ready",
    version,
    url: asset.browser_download_url,
    file: asset.name,
    size: formatSize(asset.size),
    date: release.published_at ? release.published_at.slice(0, 10) : "",
    page: release.html_url && release.html_url.startsWith("https://github.com/") ? release.html_url : RELEASES_PAGE,
  };
}

/** Asks GitHub. 404 (no release yet) and network errors both resolve to { status: "none" | "error" }. */
export async function resolveRelease(fetchImpl = globalThis.fetch, timeoutMs = 6000) {
  const ctrl = typeof AbortController === "function" ? new AbortController() : null;
  const timer = ctrl ? setTimeout(() => ctrl.abort(), timeoutMs) : null;
  try {
    const res = await fetchImpl(LATEST_API, { headers: { Accept: "application/vnd.github+json" }, signal: ctrl?.signal });
    if (res.status === 404) return { status: "none", page: RELEASES_PAGE };
    if (!res.ok) return { status: "error", page: RELEASES_PAGE };
    return describeRelease(await res.json());
  } catch {
    return { status: "error", page: RELEASES_PAGE };
  } finally {
    if (timer) clearTimeout(timer);
  }
}
