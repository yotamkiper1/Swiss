import { test } from "node:test";
import assert from "node:assert/strict";
import { chooseClip } from "../js/videos.js";

const clip = (id, ratio, extra = {}) => ({ id, ratio, userPaused: false, userPlayed: false, failed: false, ...extra });

test("plays only the most visible clip", () => {
  assert.equal(chooseClip([clip("a", 0.6), clip("b", 0.9), clip("c", 0.7)]), "b");
});

test("nothing plays while clips are mostly off screen", () => {
  assert.equal(chooseClip([clip("a", 0.3), clip("b", 0)]), null);
});

test("nothing plays while the page is hidden", () => {
  assert.equal(chooseClip([clip("a", 1)], { hidden: true }), null);
});

test("a clip the visitor paused stays paused", () => {
  assert.equal(chooseClip([clip("a", 1, { userPaused: true }), clip("b", 0.6)]), "b");
  assert.equal(chooseClip([clip("a", 1, { userPaused: true })]), null);
});

test("a clip the visitor started wins over a more visible one", () => {
  assert.equal(chooseClip([clip("a", 0.55, { userPlayed: true }), clip("b", 1)]), "a");
});

test("with reduced motion nothing starts on its own", () => {
  assert.equal(chooseClip([clip("a", 1), clip("b", 1)], { reducedMotion: true }), null);
  assert.equal(chooseClip([clip("a", 1), clip("b", 0.8, { userPlayed: true })], { reducedMotion: true }), "b");
});

test("clips that failed to load are skipped", () => {
  assert.equal(chooseClip([clip("a", 1, { failed: true }), clip("b", 0.6)]), "b");
});

test("ties go to the first clip on the page", () => {
  assert.equal(chooseClip([clip("a", 1), clip("b", 1)]), "a");
});
