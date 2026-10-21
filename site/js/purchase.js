// Buying Swiss. Payment happens on Lemon Squeezy's own checkout page: card details never touch this site,
// and there are no keys or secrets here. Lemon Squeezy emails the receipt and the download after payment.

// Paste the product's checkout link here (Lemon Squeezy ▸ Products ▸ Swiss ▸ Share), e.g.
// "https://swiss.lemonsqueezy.com/buy/1a2b3c4d-…". Empty = no Buy button on the page.
export const CHECKOUT_URL = "";
export const PRICE = "$2";

/** The checkout link if it's a real Lemon Squeezy checkout over https, otherwise null. */
export function checkoutLink(url = CHECKOUT_URL) {
  if (typeof url !== "string" || !url) return null;
  let u;
  try { u = new URL(url); } catch { return null; }
  const host = u.hostname.toLowerCase();
  const isLemon = host === "lemonsqueezy.com" || host.endsWith(".lemonsqueezy.com");
  if (u.protocol !== "https:" || !isLemon || u.username || u.password) return null;
  if (!/^\/(checkout\/)?buy\/[A-Za-z0-9-]+\/?$/.test(u.pathname)) return null;
  return u.href;
}
