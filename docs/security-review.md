# Security and privacy review

Date: 2026-11-21. Scope: the tracked source of the app, the Quick Look
extension, the share worker, the repository scripts, and the CI workflows.
This is a source review, not a penetration test or a binary audit.

**Verdict: no deliberately malicious or backdoored code was found.** Every
outbound request and every command invocation has a named product purpose,
and the two that carry user data are opt-outs or explicit user actions. The
risks worth acting on are listed at the end; the largest are the analytics
default and a Sentry DSN that is still usable in git history.

## 1. Outbound network requests

| Destination | When | Data | Notes |
| --- | --- | --- | --- |
| `us.i.posthog.com` | Once per UTC day on activation, release builds with a token | Random installation UUID, app version, macOS version, architecture, locale region, system language | On by default; Settings › Privacy turns it off. No document contents, names, paths, actions or screens. GeoIP enrichment disabled; see §6.3 for the IP caveat. |
| `release.md-preview.app` | Sparkle's automatic update check | App version and Sparkle's standard update request | Required for updates; `SUFeedURL` in `Info.plist`. |
| `api.github.com`, `github.com/*.png` | Opening the What's New/release notes UI | Repository/release identifiers; GitHub sees the request as usual | Read-only release metadata and contributor avatars. |
| `md-preview.app/s/…` | **Only when the reader chooses Share as Link** | The encrypted envelope, uploaded by the app | Encryption and key handling are in `ShareLinkCrypto`; the key is in the URL fragment and never sent. |
| Remote image hosts | Whenever a previewed document references a remote image | The reader's IP address and User-Agent reach that host | Intended for normal documents, and the preview page has no CSP. A received share blocks remote assets; Quick Look does not. See §6.1. |
| Document image hosts | **Only when sharing a document with remote images** | A GET for each image the document already shows | Upgraded to HTTPS where possible, size-capped; user-initiated. |
| `localhost:8787` | Debug builds of the share features only | Share test data | `ShareLinkSession` development base URL. |

There is no analytics of document contents, no keystroke reporting, no
clipboard upload, and no request built from a document's text or path.

## 2. Command execution

- **CLI installer** (`md-preview/App/CommandLineToolInstaller.swift`, extracted
  from `AppDelegate` during this review). Writes a shell script to a
  UUID-named temp file with mode `0700` and runs it in Terminal through
  AppleScript. The path is shell-quoted and the command is AppleScript-quoted
  (`shellQuotedString`, `appleScriptQuotedString`). The script only replaces a
  `md-preview`/`mdp`/`markdown-preview` it recognises as its own, refuses
  other files, and asks for `sudo` only when the chosen PATH directory is not
  writable. User-initiated from Settings and the app menu.
- **Relaunch helper** (`AppRelauncher`). `/bin/sh -c 'cat >/dev/null; exec
  /usr/bin/open -a "$@"'` with the bundle path and document paths as separate
  arguments; `"$@"` keeps them quoted. No string interpolation into the
  script.
- No `eval`, no `Process`/`NSTask` on document content, no downloaded code
  executed at runtime. The vendored JS is bundled with the app and served
  from the app bundle.

## 3. Web content

- The preview and editor load local HTML into `WKWebView`; scripts are the
  bundled CodeMirror/KaTeX/Highlight/Pele/DOMPurify assets.
- Document HTML passes through the app's own escaping and the viewer's
  DOMPurify sanitisation; the shared viewer ships a CSP (`viewer-csp.ts`) and
  an `X-Frame-Options: DENY` header.
- A received share's preview blocks remote image, stylesheet, font, media and
  SVG loads with a content rule list compiled in
  `ShareLinkOpener.remoteContentBlocker`, so the sender's server cannot learn
  who opened the link or when. If the list cannot be compiled, the share
  stays unrendered rather than reaching the network.
- No `allowFileAccessFromFileURLs` or disabled web security flags were found.

## 4. Secrets and history

- `POSTHOG_PROJECT_TOKEN` is injected from the gitignored `Secrets.xcconfig`;
  no real value is tracked. `SUPublicEDKey` is a public key.
- **A real Sentry DSN was committed in `Info.plist` until `abecbcd` removed
  crash reporting. It is gone from HEAD but still present in git history**
  (`git show abecbcd^:Info.plist`). A DSN is a client key, not an account
  credential, but it can be used to send events to the project and consume
  quota. **Action: delete or rotate the Sentry project/client key.**

## 5. Sandbox and entitlements

- App Sandbox on, `network.client` on (analytics, updates, share).
- `temporary-exception.files.absolute-path.read-only = /` for both targets,
  documented as the project navigator/Quick Look sibling-asset need. It is the
  broadest grant in the app: a code-execution bug could read any readable
  file. Writes still go through user selection.
- `automation.apple-events` with a `Terminal` exception for the CLI installer.
- Sparkle's `mach-lookup` names are the documented XPC services.
- No ATS exceptions were found.

## 6. Residual risks worth deciding on

1. **A previewed document can beacon to remote image hosts.** Opening an
   untrusted `.md` loads every `https` image it names, in the app and in Quick
   Look. The received-share path already blocks this. Consider a per-document
   "block remote images" control, or a CSP on the preview page as a default.
2. **Analytics is opt-out.** `UsageAnalyticsReporter.isEnabled` returns true
   when no preference is stored. The Settings copy and README describe the
   data, but the default is not called out. Consider opt-in, or an explicit
   first-run disclosure.
3. **IP addresses.** GeoIP enrichment is disabled in the event, but PostHog
   still receives the request from the reader's IP unless the project is
   configured to discard IP data (the README says it must be). Verify that
   project setting; it is outside the repository.
4. **Sentry DSN in history** (§4). Rotate it.
5. **GitHub Actions are pinned to major tags** (`actions/checkout@v7`,
   `setup-node@v7`, `upload-artifact@v7`). Pinning to commit SHAs would
   remove the tag-move supply-chain risk for a project that publishes signed
   releases.
6. **Broad read-only filesystem entitlement** (§5). Keep it while the project
   navigator needs it, but treat any new network + file-read code as
   sensitive.
7. **Share-time image downloads have no private-address guard.** A document
   can name an `http(s)` image on `localhost` or a private address; Share as
   Link fetches it and puts the bytes in the encrypted envelope. The sender
   can only see what the local network returns, and the link is encrypted,
   but a private-IP check (including after redirects) would close it.

## 7. Fixed during this review

- **A relative link could launch a local file with one click.**
  `MarkdownWebView.activateLink` sent any non-Markdown `md-asset` target to
  `NSWorkspace.open`, bypassing `ExternalLinkPolicy` (which blocks `md-asset`
  and `file`). It now opens only types the page itself may display (image,
  audio/video, PDF) via `MarkdownAssetResolution.servableFile`; a link to a
  `.command` or `.app` is ignored.
- **Quick Look followed symlinks before its containment check.** A
  `pic.png -> ~/.ssh/id_ed25519` inside the document folder passed as "inside
  the folder" and its bytes were attached. Both the folder and the candidate
  are now resolved first, so the target must be an image to be included.
- **Sharing a document over the preview limit sealed the placeholder.**
  `ShareLinkSession` rendered through `MarkdownHTML.render`, which substitutes
  the oversized-document message. Sharing now refuses with the existing
  "too large to share" message before rendering.
- **The Mermaid popup let an SVG link navigate its web view.** A link click
  is now cancelled and handed to `ExternalLinkOpener`, so the popup stays on
  its local page.
- **Quick Look shipped only English and Simplified Chinese.** Its
  `Localizable.strings` variant group now contains all six app languages
  (verified in the built `.appex`), so the new diagram labels and the
  oversized-document message stop falling back to English there.

## 8. Re-running the review

Useful starting points:

```bash
grep -rn --include='*.swift' -E 'URLSession|NSURLConnection|WKWebView|Process\(|NSTask|NSAppleScript' md-preview quick-look
grep -rn --include='*.swift' -E 'base64|eval\(|/bin/sh|osascript' md-preview quick-look
git log -S 'SentryDSN' --oneline --all
```

The vendored bundles also contain the words `fetch`, `XMLHttpRequest` and
`amplitude` (KaTeX's parser method and DOMPurify's SVG attribute list); those
are not network code. The bundled Pele, KaTeX, Highlight, DOMPurify,
Morphdom and CodeMirror versions are recorded by their `VERSION`/license
files next to them.
