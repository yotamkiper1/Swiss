import { test } from "node:test";
import assert from "node:assert/strict";
import { pickAsset, describeRelease, resolveRelease, formatSize, RELEASES_PAGE } from "../js/release.js";

const asset = (name, extra = {}) => ({
  name, size: 40_000_520, state: "uploaded",
  browser_download_url: `https://github.com/yotamkiper1/Swiss/releases/download/v1.0/${name}`, ...extra,
});
const release = (assets, extra = {}) => ({
  tag_name: "v1.0", draft: false, prerelease: false, published_at: "2026-11-02T10:00:00Z",
  html_url: "https://github.com/yotamkiper1/Swiss/releases/tag/v1.0", assets, ...extra,
});

test("prefers a disk image over a zip", () => {
  assert.equal(pickAsset(release([asset("Swiss-1.0.zip"), asset("Swiss-1.0.dmg")])).name, "Swiss-1.0.dmg");
});

test("ignores source archives, debug symbols and unfinished uploads", () => {
  assert.equal(pickAsset(release([asset("Swiss-source.zip"), asset("Swiss.dSYM.zip"), asset("Swiss-1.0.zip", { state: "starter" })])), null);
});

test("drafts, pre-releases and releases without a Mac build are not offered", () => {
  assert.equal(pickAsset(release([asset("Swiss-1.0.zip")], { draft: true })), null);
  assert.equal(pickAsset(release([asset("Swiss-1.0.zip")], { prerelease: true })), null);
  assert.equal(pickAsset(release([asset("notes.txt")])), null);
  assert.equal(pickAsset(release(undefined)), null);
  assert.equal(pickAsset(null), null);
});

test("never links off GitHub", () => {
  assert.equal(pickAsset(release([asset("Swiss.zip", { browser_download_url: "https://evil.example/Swiss.zip" })])), null);
  const d = describeRelease(release([asset("Swiss-1.0.zip")], { html_url: "https://evil.example/" }));
  assert.equal(d.page, RELEASES_PAGE);
});

test("describes a ready release with version, size and date", () => {
  assert.deepEqual(describeRelease(release([asset("Swiss-1.0.zip")])), {
    status: "ready", version: "1.0", file: "Swiss-1.0.zip", size: "40 MB", date: "2026-11-02",
    url: "https://github.com/yotamkiper1/Swiss/releases/download/v1.0/Swiss-1.0.zip",
    page: "https://github.com/yotamkiper1/Swiss/releases/tag/v1.0",
  });
});

test("sizes", () => {
  assert.equal(formatSize(6_061_767), "6.1 MB");
  assert.equal(formatSize(0), "");
  assert.equal(formatSize(undefined), "");
});

const respond = (status, body) => async () => ({ status, ok: status >= 200 && status < 300, json: async () => body });

test("no release yet (GitHub answers 404) means 'none', not an error", async () => {
  assert.equal((await resolveRelease(respond(404, { message: "Not Found" }))).status, "none");
});

test("rate limits, server errors and network failures fall back safely", async () => {
  assert.equal((await resolveRelease(respond(403, {}))).status, "error");
  assert.equal((await resolveRelease(respond(500, {}))).status, "error");
  assert.equal((await resolveRelease(async () => { throw new TypeError("offline"); })).status, "error");
  assert.equal((await resolveRelease(async () => ({ status: 200, ok: true, json: async () => { throw new SyntaxError("bad json"); } }))).status, "error");
});

test("a slow GitHub is given up on", async () => {
  const hang = (_url, { signal }) => new Promise((_, reject) => signal.addEventListener("abort", () => reject(new Error("aborted"))));
  assert.equal((await resolveRelease(hang, 20)).status, "error");
});

test("a published release resolves to its asset", async () => {
  const r = await resolveRelease(respond(200, release([asset("Swiss-1.0.dmg")])));
  assert.equal(r.status, "ready");
  assert.equal(r.file, "Swiss-1.0.dmg");
});
