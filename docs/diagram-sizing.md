# Diagram sizing — discussion notes

Status: draft, 2026-11-03. **Nothing implemented.** This captures the design
discussion around how Mermaid diagrams are sized in the preview, triggered by
the removal of the "Fill width" control.

## 1. What triggered this

- PR #593 (`4bc4331`, "put diagram and code block controls in one pill")
  removed the diagram's **Fill width / Fit diagram** toggle and added a
  **Copy** button that copies the Mermaid source. The PR says, verbatim:
  *"Diagrams trade Fill width for Copy, which copies the Mermaid source."*
- PR #611 (`c57e891`) then split that single pill into a zoom pill and an
  actions pill; the button set did not change.

So today a diagram's actions are `−` / `100%` / `+` / `Copy` / (`⛶` open in
window, app only). The Fill width toggle is gone, and the fill-width state it
controlled is gone with it.

## 2. Current behaviour (code facts)

Sizing lives in `diagramFigureSizingCSS`
(`md-preview/Rendering/MarkdownHTML+Stylesheet.swift:159`):

```css
--mm-max-height: min(70vh, 720px);
width: 100%;
aspect-ratio: var(--mm-aspect, 4 / 3);
max-height: min(var(--mm-max-height), calc(var(--mm-height, var(--mm-max-height)) + 32px));
```

- The **figure (tray) is always full column width** (`width: 100%`).
- `--mm-aspect` and `--mm-height` are set from the SVG's viewBox (`vbW`/`vbH`)
  in `MarkdownHTML+Mermaid.swift:268`.
- The SVG is `preserveAspectRatio="xMidYMid meet"` with `width/height: 100%`
  (`MarkdownHTML+Mermaid.swift:258`), so it is **letterboxed to fit** the
  figure box — scaled down when the box is small.
- The stage is `position: absolute; inset: 0; overflow: hidden;
  contain: strict` (`MarkdownHTML+Stylesheet.swift:702`), and zoom/pan is a
  CSS `transform` on the surface (`MarkdownHTML+Mermaid.swift:408`). Zoom
  never reflows the document.
- `⛶ Open in Window` (app only) already provides a full-size escape hatch.

Consequence: a tall/narrow diagram (e.g. `vbW=400`, `vbH=1600`) is capped at
720px high and shrunk to fit, rendering around 172px wide — **uniformly
scaled down, not distorted**.

## 3. What "Fill width" actually did

The old toggle added `.mermaid-width-expanded { max-height: none }`. Since the
figure was already `width: 100%`, it did **not** change the width — it removed
the height cap so the box grew to `columnWidth × vbH / vbW`. That made the
diagram scale up to the column width **and grew the figure's height, pushing
the rest of the document down** (a reflow).

| | Fill width (removed) | Current zoom |
| --- | --- | --- |
| Mechanism | drop `max-height`, re-layout | `transform: scale()` inside a clipped stage |
| How the diagram grows | scales to column width, **tray grows** | overflows and is cropped; pan to see more |
| Reflows the document | **yes** — content below moves down | no — layout is untouched |

They are therefore **not interchangeable**. Fill width was a distinct in-flow
enlargement, not a redundant copy of zoom.

## 4. Options discussed

### 4.1 Restore Fill width (button only)

Smallest change: re-add the `mermaid-width-expanded` class, `toggleWidth()`
and the ⤢/⤡ button to the actions pill. Cost: it reintroduces the reflow and
the tall-diagram blow-up (§3).

### 4.2 Make it a setting, default on

Two distinct readings:

- **A — render default**: all diagrams render fill-width unless turned off.
- **B — button + default state**: restore the per-diagram toggle, and a
  preference controls its initial state.

Risks of A as a *default*:

- Fill width is a **per-diagram** property (depends on each diagram's aspect
  ratio). A global default is a blunt instrument.
- Tall/narrow diagrams blow up (`columnWidth × vbH/vbW` can be several
  screens), so a global default makes every such diagram dominate its page —
  the "document height grows" effect applied to everything.
- It inverts the current deliberate design: diagrams draw at natural size, not
  upscaled (comment at `MarkdownHTML+Stylesheet.swift:154`).

Scope notes:

- A setting would follow the existing pattern (`documentFont`,
  `readerLayout`, `textAlignment` are passed into `render(...)` with
  `.current` defaults — `MarkdownHTML.swift:317`). Natural home:
  `Features/Settings/ReadingSettingsView.swift`.
- It affects the app, Quick Look and the editor (shared CSS/JS). It **does
  not** affect the share viewer, which serves static generated CSS
  (`server/share-worker/viewer/generated/markdown.css`) to a reader who has
  no app settings.
- It is a global preference: not per-document, not per-diagram.

### 4.3 Dynamic height

Let the figure height follow the diagram so tall diagrams are not shrunk. In
practice this means relaxing the `min(70vh, 720px)` term; height becomes
`min(columnWidth × vbH/vbW, vbH + pad)`.

| | Approach | Effect | Cost |
| --- | --- | --- | --- |
| A | drop the cap entirely | never shrinks | pathological diagrams make very long pages |
| B | raise the cap (e.g. `min(150vh, 1600px)`) | common tall diagrams show at natural height | page bounded to ~1.5–2 screens |
| C | keep cap, render at natural size, allow internal pan | page length unchanged | needs interaction; conflicts with existing drag/zoom |

The cap exists on purpose — the code comment says *"capped by max-height so
massive diagrams don't push the page."* Dynamic height trades page length for
not shrinking.

### 4.4 Natural size, clamped (preferred direction)

Display the diagram at its **natural size**, and only scale it **down** when
it does not fit — never up. Concretely:

- `max-width: 100%` (shrink only if wider than the column);
- `max-height: <a comfortable ceiling>` (shrink only if taller than the
  ceiling);
- size the tray to the drawing (`fit-content`) rather than forcing
  `width: 100%`, and centre it.

| Diagram | Current (full-width tray + 720 cap) | Natural size + clamp |
| --- | --- | --- |
| small / medium | natural size, but tray still full width | natural size, tray shrinks to the drawing |
| wide | scaled to column width | scaled to column width (same) |
| tall | hard-capped at 720, shrunk small | natural height until the ceiling, then shrunk |

This is neither Fill width (no upscaling) nor dynamic-height (no unbounded
growth); it is "size to content, clamp to fit". The `vbW`/`vbH` needed for it
are already available (`--mm-aspect` / `--mm-height`).

The one knob that remains is the **height ceiling** — the same page-length vs
no-compression trade-off as §4.3:

- keep the page short → `~70vh`;
- keep tall diagrams unshrunk → `150–200vh` or none;
- compromise → a fixed ceiling (`~1200–1600px`), only pathological diagrams
  trigger it.

A secondary decision: whether the tray **shrinks to the drawing** (loses
alignment with code blocks' full-width trays) or stays full width while only
the drawing uses natural size.

## 5. Trade-off summary

| Concern | Effect |
| --- | --- |
| Fill width default | global reflow; tall diagrams dominate pages |
| Dynamic height | fixes compression; pages get longer |
| Natural size + clamp | fixes "full width / full height" complaints; height ceiling decides page length |
| Per-diagram control | matches the per-diagram nature of the problem, but adds a button |
| Share viewer | unaffected by any app setting (static CSS) |

## 6. Open questions

1. Semantics: global render default (A) vs restore the button plus a default
   state (B)?
2. Height ceiling: `~70vh`, `~150vh / 1600px`, or none?
3. Tray: shrink to the drawing, or stay full width?
4. Is "natural size + clamp" the target model, or is an explicit
   Fit / Fill-width switch still wanted on top of it?
5. Should any of this be exposed in Settings, and if so, which pane?

## 7. Code locations referenced

- `md-preview/Rendering/MarkdownHTML+Stylesheet.swift:159` —
  `diagramFigureSizingCSS` (sizing), `:702` — `.mermaid-stage`.
- `md-preview/Rendering/MarkdownHTML+Mermaid.swift:258` — SVG normalisation
  (`meet`, 100%), `:268` — `--mm-aspect` / `--mm-height`, `:408` — `apply()`
  zoom transform.
- `md-preview/Rendering/MarkdownHTML.swift:317` — `render(...)` settings
  parameters (`.current` pattern).
- `md-preview/Features/Settings/ReadingSettingsView.swift` — likely settings
  home.
- `server/share-worker/viewer/generated/markdown.css` — static viewer CSS
  (not affected by app settings).
- PR #593 (`4bc4331`) — removed Fill width, added Copy. PR #611 (`c57e891`)
  — split the pill.
