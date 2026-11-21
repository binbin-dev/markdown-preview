# Maintainability backlog

Ranked by how much each item makes future changes harder. None of these is a
current bug; they are the structural debt that survived the 2026-11-21
cleanup. File and line numbers were accurate then.

## P1 — God files

1. **`AppDelegate.swift` (~1,550 lines).** Lifecycle, settings application,
   URL handling, and ~600 lines of menu construction
   (`installNewTabMenuItem` … `codeTitles`). Extract an `AppMenuInstaller`
   (menus + the context-menu copies) so a menu addition stops touching a
   1,500-line file. The CLI installer is already out
   (`CommandLineToolInstaller.swift`). Effort: medium. Risk: low (mechanical).
2. **`EscapingHTMLFormatter.swift` (2,010 lines) holds four unrelated
   types:** `MarkdownHighlightSource` (14–707), `TaskCheckboxSource`
   (708–737), `MarkdownTableEdit`/`MarkdownTableSource` (738–980), and
   `EscapingHTMLFormatter` (981–2010). Split along those boundaries. Effort:
   small. Risk: low.

## P2 — Large controllers

3. **`MarkdownWebView.swift` (2,075 lines):** WebKit setup, render pipeline,
   find/highlight JS, scroll metrics, zoom, HUD, link policy. The scroll and
   zoom engines already have clean seams; extract them first. Effort: medium.
   Risk: medium (stateful callbacks).
4. **`ContentViewController.swift` (993 lines):** snapshot overlay, chrome
   insets, navigation retry, scrollspy, scroll-anchor restore. Extract
   `PreviewSnapshotOverlayController` and `PreviewScrollspy`. Effort: medium.
   Risk: medium.
5. **`MainSplitViewController.swift` (975 lines):** edit-mode orchestration
   (`440–775`) plus layered chrome constraints. The UUID-generation and
   pending-completion protocol is the fragile part; an explicit state machine
   would help. Effort: large. Risk: medium-high.
6. **`FocusRingVisibility` walks every window and subview on every click,
   twice.** It is correct and cheap enough today, but it mutates AppKit
   controls globally, including future embedded ones. Limit it to the key
   window, or cache the traversal and re-run only on window changes. Effort:
   medium. Risk: medium.

## P2 — A test that fails on a non-English Mac

`FileSearchRegressionTests.testScoresOrderingAndHighlightsMatchThePreviousImplementation`
compares the exact order of equal-score results. `FileSearchMatcher.isOrderedBefore`
breaks ties with `localizedStandardCompare`, which uses the process locale, and
the recorded baseline was made under English collation. On this machine
(`AppleLocale = zh_CN`) three tie pairs swap and the test fails every run; CI
runs under an English locale and passes. The code, test and fixture are
identical to `main`, so this predates the 2026-11-21 cleanup. Fix by pinning
the locale for the test, or by asserting scores, match sets and per-file
highlights while treating the order within a tie as locale-dependent.

## P3 — Single sources of truth

7. **Markdown extension lists are duplicated and disagree.**
   - `Rendering/MarkdownWebView.swift:1763` — md, markdown, mdown, mkdn, mkd, mdx
   - `Features/FileSearch/ProjectFileIndex.swift:26` — adds mdwn
   - `Features/OpenWith/OpenTargetCatalog.swift:125` — only four of them
   - `Document/DocumentWindowController+OpenTargets.swift:502` and
     `App/MarkdownDocumentController.swift:17` — md, markdown, mdown, mdx, txt

   A `.mdwn` link (declared in `Info.plist`) opens externally instead of in
   the app. One `MarkdownFileExtensions` type with named sets (`navigable`,
   `openable`, `indexable`) and a comment per set. Effort: small. Risk: low.
8. **Raw preference strings.** `"MarkdownPreview.opensMarkdownLinksInNewWindows"`
   appears three times in `SettingsModel.swift`; `"MarkdownPreview.outlineFollowsPointer"`
   is split between `ContentViewController` and `ReadingSettingsView`. A
   `PreferencesKeys` enum removes the typo risk. Effort: small. Risk: low.
9. **Literal `⛶`** is used in `MarkdownHTML+Mermaid.swift:57` and
   `BlockGlassHUD.swift:75`, with a stylesheet rule keyed to it. One constant.
   Effort: trivial. Risk: low.
10. **Unused localization keys** (verified absent from Swift/JS/XIB):
    `"Red Graphite"`, `"Charcoal"`, `"Hand-off"`, `"Editor background"`,
    `"Sidebar options"`, `"Edit Table"`, `"Edit Table Cell"`, `"Open a folder
    to search its files"`, `"↑↓ browse · ↩ open …"`, and two old theme-copy
    sentences. Removing them from all six `.lproj` files is safe once a
    translator confirms none is used by a future string. Effort: small.

## P4 — Supply chain and CI

11. **GitHub Actions use major tags** (`actions/checkout@v7`,
    `setup-node@v7`, `upload-artifact@v7`). Pin to commit SHAs for a project
    that publishes signed releases.
12. **`scripts/bundle-katex.py` and `scripts/bundle-highlight.py`** fetch
    pinned versions from a CDN and commit the bytes without checking a hash.
    Developer-run only, but a checksum would make the vendoring auditable.

## Done in the 2026-11-21 cleanup

- CLI installer moved out of `AppDelegate`.
- `SharedLook` gained a single `current(from: model)` comparison; the
  hand-written seven-field check is gone.
- `applyAutoSaveIntervalSetting` / `applyThemeColorsSetting` use
  `documentWindowControllers`.
- `rewrite` and `replaceMatchesWithFullMatch` share one matching loop.
- Duplicate `Link`/`Normal` localization keys removed; parity, duplicate-key
  and format-specifier checks now run in CI.
- `DocumentSizePolicy.exceedsPreviewLimit` is used by both callers; the
  redundant launch guard is gone.
- `tests/.../MarkdownTOC.swift` is a symlink, not a copy.
- `scripts/check-math-html.py` points at the current files and runs in CI.
- Quick Look ships all six languages.
- Local-link opening is restricted to displayable types; Quick Look resolves
  symlinks before the containment check; sharing refuses oversized documents
  instead of sealing the placeholder.
