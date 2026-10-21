import { test } from "node:test";
import assert from "node:assert/strict";
import { kindOf, organize } from "../js/wand.js";

test("links, pictures, files and notes", () => {
  assert.equal(kindOf("https://en.wikipedia.org/wiki/Woolly_mammoth"), "link");
  assert.equal(kindOf("www.are.na"), "link");
  assert.equal(kindOf("https://example.com/poster.jpg?w=800"), "picture");
  assert.equal(kindOf("Lyuba – hero print.jpg"), "picture");
  assert.equal(kindOf("lyuba.HEIC"), "picture");
  assert.equal(kindOf("Exhibition plan.pdf"), "file");
  assert.equal(kindOf("Opening night: 14 November."), "note");
  assert.equal(kindOf("The woolly mammoth began to diverge from the steppe mammoth about 800,000 years ago."), "note");
});

test("empty input is nothing", () => {
  assert.equal(kindOf(""), null);
  assert.equal(kindOf("   "), null);
  assert.equal(kindOf(undefined), null);
});

test("the wand keeps Swiss's folder order and drops empty folders", () => {
  const items = [
    { text: "a", kind: "note" }, { text: "b", kind: "link" }, { text: "c", kind: "picture" }, { text: "d", kind: "link" },
  ];
  assert.deepEqual(organize(items).map(f => [f.name, f.items.length]), [["PhotoBook", 1], ["Linker", 2], ["Notepad", 1]]);
});
