# Ticket — Mermaid diagrams at natural size, with Fill width restored

- **Status:** ready for implementation
- **Created:** 2026-11-03
- **Branch:** `feat/mermaid-natural-size-and-fill-width`
- **Base:** `upstream/main` @ `78b0541`
- **Design discussion:** `docs/diagram-sizing.md` (local, untracked — read it, do
  not commit it)

## 1. Problem

PR #593 (`4bc4331`) removed the diagram's **Fill width / Fit diagram** toggle
and replaced it with **Copy**. The tray stayed at the column's width (which
this ticket keeps), but the height ceiling is `min(70vh, 720px)`, so:

- a tall/narrow diagram shrinks to a narrow sliver (for example `vbW=400`,
  `vbH=1600` renders about 172 px wide);
- there is no way to deliberately enlarge a diagram in the document flow.

The current code already avoids *upscaling* the drawing. See
`docs/diagram-sizing.md` §2–§4.

## 2. Goal

1. **Default to natural size inside the original full-width tray.** The tray
   stays the column's width (as before), and only scales the drawing *down*
   when its natural height would not fit the column or a height ceiling.
2. **Restore the per-diagram Fill width toggle**, with its old in-flow
   semantics: the tray is already full width, so the height cap is removed,
   the tray grows taller, and the document below reflows.
3. Keep the preview, Quick Look, Edit Mode, and the share viewer consistent.

This is the "natural size + clamp" direction in `docs/diagram-sizing.md` §4.4
plus the restored button from §4.1. It is **not** a global setting (§4.2 A/B).

## 3. Decisions

- **Height ceiling:** `min(150vh, 1600px)`. This is the compromise from §4.4:
  common tall diagrams keep their natural height, while pathological diagrams
  cannot make the page arbitrarily long. The ceiling lives in one CSS custom
  property (`--mm-max-height`) so it can be changed in one place later.
- **Tray:** keep the original full column width. The drawing is centred inside
  it, and the tray's height follows the drawing (clamped by the height
  ceiling) instead of the tray shrinking to the drawing's width.
- **Fill width:** per-diagram only, not a preference and not persisted. It is
  the old reflow behaviour (drop the height cap, let the tray grow taller),
  not a second kind of zoom.
- **Padding:** the 16 px stage inset is part of the natural height. A diagram
  with viewBox `vbW × vbH` uses a height of `vbH + 32` at natural size; the
  tray's width stays the column. The drawing is never upscaled in the default
  state.
- **Icons:** Fill width is a **horizontal double arrow**, so it does not read
  as the window button. Open in Window goes back to the 0.0.69 glyph `⛶`
  instead of 0.0.70's diagonal-arrow line icon, which looked too much like
  Fill width.
- **Share viewer:** keep working. It serves generated copies of the app's CSS
  and wiring, and `main.js` currently rewrites `data-mm-act="width"` to
  `copy`; that migration must go, because Fill width is now a real button
  again.

## 4. Implementation

### 4.1 Sizing variables (preview and editor)

In `md-preview/Rendering/MarkdownHTML+Mermaid.swift`, `attachZoom` already sets
`--mm-aspect` and `--mm-height` from the viewBox (around line 268). Keep just
those two variables: the tray width stays the column, so no natural-width
variables are needed.

Do the same in `scripts/editor-bundle/entry-cm.js` (the `MermaidWidget.figure`
method, around lines 426–427) — it already sets `--mm-aspect` and
`--mm-height`; leave it that way. Rebuild
`md-preview/Vendor/CodeMirror/mdedit.min.js` with `npm ci && npm run build`
from `scripts/editor-bundle` after any edit.

### 4.2 CSS

Replace `MarkdownHTML.diagramFigureSizingCSS`
(`md-preview/Rendering/MarkdownHTML+Stylesheet.swift:159`) with the original
full-width tray, keeping the raised ceiling:

```css
--mm-max-height: min(150vh, 1600px);
width: 100%;
aspect-ratio: var(--mm-aspect, 4 / 3);
max-height: min(var(--mm-max-height), calc(var(--mm-height, var(--mm-max-height)) + 32px));
```

Why this works:

- the tray keeps the column's width, like a code block;
- a small diagram's natural height is `vbH + 32`, because the height cap is
  `min(ceiling, vbH + 32)`, so the drawing is not upscaled;
- a wide diagram follows its aspect ratio within the column;
- a tall diagram is capped at the ceiling instead of the old 70vh/720px, so
  ordinary tall diagrams keep most of their natural size.

Add the expanded state near the other `.mermaid-figure` rules:

```css
.mermaid-figure.mermaid-width-expanded {
    max-height: none;
}
```

The error state already overrides `aspect-ratio`, `max-width` and
`max-height`; leave that behaviour alone. The editor shares
`diagramFigureSizingCSS`, so it gets the same full-width sizing automatically;
the expanded class is preview-only.

Update the doc comment above `diagramFigureSizingCSS` to describe this
full-width + natural-height behaviour.

### 4.3 Preview HUD (HTML)

In `MarkdownHTML+Mermaid.swift`:

- Add localized labels:
  - `Fill width` (comment: "Mermaid diagram fill width button")
  - `Fit diagram` (comment: "Mermaid diagram fit button")
- Emit a width button in `.mermaid-hud-actions`, before Copy:

```html
<button type="button" class="mermaid-hud-btn mermaid-hud-width"
        data-mm-act="width" tabindex="-1"
        aria-label="Fill width" aria-pressed="false"
        title="Fill width"></button>
```

- Add `fillWidth` and `fitDiagram` to `diagramMessagesJS`.
- Add the action to `runHudAction`:

```js
case 'width': toggleWidth(figure); break;
```

- Restore `toggleWidth(figure)`:

```js
function toggleWidth(figure) {
    const expanded = figure.classList.toggle('mermaid-width-expanded');
    const btn = figure.querySelector('[data-mm-act="width"]');
    if (btn) {
        const label = expanded ? messages.fitDiagram : messages.fillWidth;
        btn.setAttribute('aria-label', label);
        btn.setAttribute('aria-pressed', String(expanded));
        btn.setAttribute('title', label);
    }
    reset(figure);
    requestAnimationFrame(() => {
        cacheRect(figure);
        window.dispatchEvent(new Event('md-preview-mermaid-rendered'));
        if (diagramHUD?.target === figure) diagramHUD.refresh();
    });
}
```

- Add `width` to the `labelHud` map.
- Add `expanded: figure.classList.contains('mermaid-width-expanded')` to the
  object returned by the `diagramHUD` describe closure.

Add CSS icons next to the existing HUD icon rules:

```css
.mermaid-hud-btn[data-mm-act="width"] {
    --mm-icon: \(diagramHUDIcon("<path d='M4 12h16M8 8l-4 4 4 4M16 8l4 4-4 4'/>"));
}
.mermaid-figure.mermaid-width-expanded .mermaid-hud-btn[data-mm-act="width"] {
    --mm-icon: \(diagramHUDIcon("<path d='M4 12h4M16 12h4M8 8l4 4-4 4M16 8l-4 4 4 4'/>"));
}
```

(The first is a horizontal double arrow; the second is the inward version.)

Restore the 0.0.69 Open in Window glyph. The popup button is emitted as:

```html
<button type="button" class="mermaid-hud-btn mermaid-hud-popup"
        data-mm-act="popup" tabindex="-1"
        aria-label="Open in Window" title="Open in Window">⛶</button>
```

and the mask icon is suppressed for it:

```css
.mermaid-hud-btn[data-mm-act="popup"]::before { content: none; }
.mermaid-hud-btn[data-mm-act="popup"] { font-size: 16px; line-height: 12px; }
```

Quick Look does not emit the popup button, so only the app's HTML HUD shows
the glyph.

### 4.4 Native glass HUD (macOS 26)

`md-preview/Rendering/BlockGlassHUD.swift`:

- Add `var expanded = false` to `BlockGlassHUD.Block`.
- Add `private let widthButton = HUDButton(act: "width", width: 24)`.
- Include it in the actions glass: `[wrapButton, widthButton, copyButton,
  popupButton]`.
- Hide it for code blocks (`widthButton.isHidden = !isDiagram`).
- Include `expanded` in the `laidOut` content tuple so a toggle re-lays out.
- For diagrams, set the symbol and label from `block.expanded`:
  - false → `arrow.left.and.right`, label **Fill width**
  - true → `arrow.right.and.line.vertical.and.arrow.left`, label **Fit diagram**
- Restore the Open in Window glyph instead of a diagonal-arrow SF Symbol:
  add `HUDButton.setGlyph(_:label:)` (a system font, not the monospaced level
  font) and initialise the popup button with `setGlyph("⛶", label: ...)`.
- Parse `expanded` in `MarkdownWebView.updateBlockGlassHUD`
  (`message["expanded"] as? Bool ?? false`).

The host click path already forwards `width` through `mdpDiagramHUDAction` →
`runHudAction`; the existing `requestAnimationFrame` refresh in that closure
then updates the native label state.

### 4.5 Localization

Add the two English strings to all five app strings files, reusing the
translations that existed before PR #593:

| Language | Fill width | Fit diagram |
| --- | --- | --- |
| en | Fill width | Fit diagram |
| fa | پر کردن عرض | برازش نمودار |
| ja | 幅に合わせる | ダイアグラム全体を表示 |
| pl | Wypełnij szerokość | Dopasuj diagram |
| zh-Hans | 填满宽度 | 适应图表 |

The share-viewer test requires a translation for every message in
`diagramMessagesJS`, so both keys must be present in every `.lproj`.

### 4.6 Share viewer

`server/share-worker/viewer/main.js` has a DOMPurify hook that migrates old
shared pages:

```js
if (node.dataset.mmAct === "width") {
  node.dataset.mmAct = "copy";
  ...
}
```

Remove that width → copy migration and update the comment. The viewer keeps
the width button (the hook already preserves every non-`popup` HUD action and
clears its text so the CSS icon shows).

Then regenerate the shared files rather than editing them by hand:

```bash
MDP_WRITE_VIEWER_KIT=1 swift test --package-path tests/swift-tests \
  --filter ShareViewerKitTests
```

That rewrites `server/share-worker/viewer/generated/markdown.css` (the new
sizing CSS and width icon) and `generated/diagrams.js` (the restored
`toggleWidth` and messages).

## 5. Tests

Update/add in `tests/swift-tests/Tests/MarkdownHelpersTests/`:

- `MarkdownHTMLRenderTests`
  - Extend `testMermaidPopupButtonIsEmitted` (or add
    `testMermaidFillWidthButtonIsEmitted`) to assert:
    - `class="mermaid-hud-btn mermaid-hud-width"` and
      `data-mm-act="width"` are emitted;
    - `mermaidInitWiring` contains `function toggleWidth`,
      `case 'width'` and `mermaid-width-expanded`.
  - Add a WKWebView layout test for the default state: set
    `--mm-aspect: 2 / 1`, `--mm-height: 200px`, `--mm-max-height: 600px` on a
    900 px article and assert the figure keeps the article width and is
    `232px` tall (the natural height `vbH + 32`), not 450px.
  - Add a wide-diagram case: `--mm-aspect: 4 / 1` keeps the article width and
    follows the aspect ratio while it fits.
  - Add a tall-diagram case: `400 × 1600` with a `600px` ceiling keeps the
    article width and is `600px` tall.
  - Add a test that clicks `[data-mm-act="width"]` and asserts the width stays
    the article width, `max-height` no longer clamps it, the height grows to
    the diagram's aspect ratio, `aria-pressed` flips to `"true"`, and clicking
    again restores the capped height.
  - Assert the emitted popup button still contains `⛶` and that the
    stylesheet carries the horizontal-arrow Fill width icon.
- `MixedMarkdownLayoutTests` / `EditorPreviewLayoutTests`: they compare read
  and editor boxes. They should continue to pass; adjust only if the natural
  sizing exposes a real read/editor mismatch.
- `ShareViewerKitTests`: run the generator and commit the regenerated files.

`scripts/check-mermaid-html.py`: add a check for the Fill width button
(`data-mm-act="width"`, `function toggleWidth`, `mermaid-width-expanded`) so
the smoke script covers the restored control.

## 6. Local `.app` build script

Add `scripts/build-app.sh` (executable, zsh). Requirements:

- Build the `md-preview` scheme into a real `.app` under `build/`, default
  configuration `Debug` (bundle id `doc.md-preview.dev`, so it can live beside
  a release install), with `release` / `--configuration release` available.
- Sign with the user's **personal Apple Development certificate**, not the
  upstream team in `project.pbxproj`.
- Never edit `md-preview.xcodeproj/project.pbxproj`; pass overrides on the
  `xcodebuild` command line, and fail if the project file changed.
- Auto-detect the identity with:
  `security find-identity -v -p codesigning`, preferring an
  `Apple Development:` identity. Allow `--identity` and `--team` overrides,
  plus `MDP_CODESIGN_IDENTITY` / `MDP_DEVELOPMENT_TEAM` environment overrides.
- Derive the team id from the certificate's `OU` (for example with
  `security find-certificate -c "<identity>" -p | openssl x509 -noout -subject`),
  unless `--team` is given.
- Build with automatic signing so the embedded Quick Look extension and
  Sparkle helpers are signed too:

```bash
xcodebuild -project md-preview.xcodeproj -scheme md-preview \
  -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates build
```

  (Automatic signing rejects a full identity string in `CODE_SIGN_IDENTITY`;
  the team override is what pins the personal certificate. Verify the
  resulting `Authority` line matches the detected identity.)
- Copy the product with `ditto` into a `mktemp -d` staging directory under
  `build/`, run `xattr -cr` on it, then atomically move it to
  `build/Markdown Preview.app`. Debug builds replace the previous app outright
  because they are rebuilt all day; Release builds preserve the previous app
  as `Markdown Preview.previous.<epoch>.app`.
- Verify with `codesign --verify --deep --strict --verbose=2`,
  `plutil -lint`, and `codesign -dr -` (fail if the designated requirement
  contains `cdhash`). Print `codesign -dv --verbose=4` to stderr so the
  personal identity is visible; print only the final `.app` path on stdout.
- Print the final `.app` path; `--open` launches it after verification.
- Exit 64 for usage, 69 for missing/unusable signing identity, 70 for a build
  or signing-verification failure. If provisioning fails because the personal
  team lacks App Groups / App Sandbox capabilities, print the exact failing
  capability and the hint to sign Xcode in with that Apple ID — do not
  silently fall back to the upstream team or ad-hoc signing.

## 7. Acceptance criteria

- [ ] The tray keeps the original full column width; it does not shrink to the
      drawing.
- [ ] A small diagram keeps its natural height `vbH + 32`; it is not
      upscaled.
- [ ] A wide diagram follows its aspect ratio within the column; a tall one
      is capped at the height ceiling while keeping the full-width tray.
- [ ] Empty and error diagrams keep their current in-flow text layout.
- [ ] Hovering a diagram shows Fill width next to Copy (and Open in Window in
      the app). Fill width is a horizontal double arrow; Open in Window shows
      the 0.0.69 `⛶` glyph. The tooltip and `aria-pressed` invert when
      toggled.
- [ ] Fill width removes the height cap, grows the tray taller, reflows the
      document, and resets zoom to 100%. Toggling back restores the natural
      height; the width stays the column throughout.
- [ ] The macOS 26 native glass pill shows the same state, and its label
      switches between Fill width and Fit diagram.
- [ ] Quick Look and the share viewer keep working; the share viewer's old
      width → copy migration is gone.
- [ ] Edit Mode's diagram widget uses the same full-width tray and natural
      height.
- [ ] `python3 scripts/check-mermaid-html.py` passes.
- [ ] Targeted Swift tests pass; the regenerated share-viewer files are
      committed.
- [ ] `scripts/build-app.sh` produces a `.app` signed by the personal Apple
      Development identity, and launching it shows the new behaviour.
- [ ] `git diff -- md-preview.xcodeproj/project.pbxproj` is empty.

## 8. Commits and cherry-pick workflow

Keep the work in three independent commits so it can be cherry-picked onto
future upstream `main`:

1. `docs: add ticket for natural-size Mermaid diagrams and Fill width`
2. `feat (preview): draw Mermaid diagrams at natural size and restore Fill width`
   — includes Swift, strings, editor bundle, tests, share viewer generated
   files and `main.js`.
3. `build: add local .app build script with personal signing`

Do **not** commit `docs/diagram-sizing.md` unless the user asks; it is a local
working note and its "Nothing implemented" status would become stale.

Later, after upstream moves:

```bash
git fetch upstream
git switch -c my-upstream-plus-diagrams upstream/main
git cherry-pick <ticket-sha> <feature-sha> <build-script-sha>
```

## 9. Validation

```bash
python3 scripts/check-mermaid-html.py

# Rebuild the editor bundle after editing entry-cm.js
(cd scripts/editor-bundle && npm ci && npm run build)

# Rewrite and then verify the share viewer copies
MDP_WRITE_VIEWER_KIT=1 swift test --package-path tests/swift-tests \
  --filter ShareViewerKitTests

swift test --package-path tests/swift-tests --parallel \
  --filter 'MarkdownHTMLRenderTests|EditorPreviewLayoutTests|MixedMarkdownLayoutTests|ShareViewerKitTests'

scripts/build-app.sh debug --open
```

Manual check with `samples/mermaid-heavy.md`: resize the window from wide to
narrow, hover every diagram, toggle Fill width on a tall one, and confirm the
document reflows, the tray keeps the column width, and toggling back restores
the natural height.

## 10. Out of scope

- A global "default to Fill width" preference or a Settings pane.
- Persisting the expanded state per diagram or per document.
- Changing the zoom/pan model (zoom remains a clipped CSS transform).
- Notarization, Sparkle appcast changes, or release/version bumps.
- Changing the upstream team id or any signing setting in the Xcode project.
