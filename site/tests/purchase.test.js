import { test } from "node:test";
import assert from "node:assert/strict";
import { checkoutLink, CHECKOUT_URL } from "../js/purchase.js";

test("no link configured means no Buy button", () => {
  assert.equal(checkoutLink(""), null);
  assert.equal(checkoutLink(undefined), null);
  assert.equal(CHECKOUT_URL === "" ? checkoutLink() : "set", CHECKOUT_URL === "" ? null : "set");
});

test("accepts real Lemon Squeezy checkout links", () => {
  assert.equal(checkoutLink("https://swiss.lemonsqueezy.com/buy/1a2b3c4d-5e6f"), "https://swiss.lemonsqueezy.com/buy/1a2b3c4d-5e6f");
  assert.equal(checkoutLink("https://swiss.lemonsqueezy.com/checkout/buy/1a2b3c4d"), "https://swiss.lemonsqueezy.com/checkout/buy/1a2b3c4d");
});

test("refuses anything that only looks like one", () => {
  for (const bad of [
    "http://swiss.lemonsqueezy.com/buy/abc",            // not https
    "https://lemonsqueezy.com.evil.example/buy/abc",    // look-alike host
    "https://evillemonsqueezy.com/buy/abc",             // no dot before the domain
    "https://user:pass@swiss.lemonsqueezy.com/buy/abc", // credentials in the link
    "https://swiss.lemonsqueezy.com/admin",             // not a checkout
    "javascript:alert(1)",
    "not a url",
  ]) assert.equal(checkoutLink(bad), null, bad);
});
