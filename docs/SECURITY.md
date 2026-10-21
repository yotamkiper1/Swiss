# Swiss security report

Swiss is a local macOS app: no server, no account, no database online. This goes through the usual web-app
security checklist and says what each item means for Swiss. Last checked: October 2026, Swiss 1.0.

| # | Checklist item | Status | What it means for Swiss |
|---|---|---|---|
| 1 | Hide API keys, check env variables, check git for secrets | **Done** | The whole git history was searched for keys, tokens, private keys, SMTP settings and personal paths: none. The only address in the code is the public feedback address. The app has no mail password, OAuth secret or API key inside it. Env variables that change what Swiss runs or where its library lives (`STASH_YTDLP`, `STASH_LAME`, `STASH_LIBRARY`, `STASH_COUNTERS`) only work in Swiss Test. |
| 2 | Proper authentication, user access, hashing passwords | **Done** (no login) | Swiss has no accounts, so there are no passwords to store or hash. The optional **Touch ID lock** (Settings ▸ Privacy) uses macOS's own prompt; Swiss never sees a password. If Sign in with Apple / Google comes with sync: `ASWebAuthenticationSession` only, tokens in the Keychain, never a password form. Swiss's folders (`~/Documents/.Stash`, `.stash`, Application Support ▸ Stash) are set to owner-only (0700). |
| 3 | Protect admin routes, secure endpoints, rate limiting | **Done** | Swiss's "endpoints" are its links, which any web page can open: `swiss://add`, `swiss://recent?text=`, `swiss://clipboard`. They're limited to 5 per 10 seconds, carry text only (20,000 characters at most), can't open or run files, and `swiss://clipboard` never takes a password. The test hooks (`stashtest://debug…`) are **compiled out** of the real app (`#if SWISS_TEST`, only `./build.sh test` sets it). The Services menu item and the Chrome extension only add to Recent. |
| 4 | Sanitize input, XSS, CORS, security headers | **Done** | Text from links has control characters and right-to-left tricks removed. Link titles from web pages are plain text, 300 characters at most; their pictures are re-drawn as small previews. The YouTube player loads only a checked video id; links and pop-up windows inside it open in the browser, never in Swiss. File names: downloads go into a fresh folder per download, and yt-dlp makes names safe. CORS and HTTP headers: not applicable (no server). |
| 5 | Debug mode off | **Done** | Timing logs, counters and test hooks run only in Swiss Test; the real app logs nothing about your content. |
| 6 | Update dependencies, remove unused packages | **Done** | No third-party Swift packages. Bundled yt-dlp is the latest release (2026.08.19) and its SHA-256 matches the official checksum list; it can update itself from Settings ▸ Tools. LAME 3.100 is the last release. The unused `Unused/` folder was removed. |
| 7 | Exposed files | **Done** | The public repo holds code, design screenshots made with demo content, and the film tooling; no personal data. Temporary copies (drags, shares) are deleted at every launch. The Downloads ▸ Swiss watcher only links files, it never opens or runs them. |
| 8 | Secure database access | **Done** | The library is a local JSON file, written in the background, checked by reading it back, and swapped in atomically, with the last good copy and hourly backups kept. A damaged library or Recent list is set aside, never overwritten. Folders are owner-only (see 2). Note: `~/Documents` syncs to iCloud if Desktop & Documents is on. |
| 9 | Full security audit | **Done** | This file. Also: Hardened Runtime on the app and its tools (only yt-dlp may load its own unpacked Python libraries), the only entitlement is Apple Events (to arrange Finder windows), files that can run code ask first, downloads are quarantined like Safari's, and password managers' clipboard items are never captured. |

## Still open

- **Signing and notarization** need a paid Apple Developer account (see the README's launch checklist). Until then other Macs show a Gatekeeper warning.
- **Apple silicon only**: the app and its MP3 encoder are arm64.
- A picture dragged in from a web page is downloaded whole into memory (no size cap). Low risk; you have to drag it in yourself.
