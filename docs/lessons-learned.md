# Lessons from the Mermaid / focus-ring / oversize run

This is a retrospective on the work merged between 2026-11-03 and 2026-11-18
on `feat/mermaid-natural-size-and-fill-width` and on `main`. It records the
failures that made the branch expensive to finish, so the next change can
avoid them. It is not a blame list: each item names the evidence and the rule
that replaces the habit.

The recurring theme is that a change was called done when it *built* or when
the happy path worked, rather than when the failing interaction had been
reproduced and the common path re-checked.

## 1. What went wrong

### 1.1 A fix was merged without reproducing the failing interaction

`4ea77f2`, `bef59d8` and `31c1c9c` made focus rings follow "the last input was
the keyboard", implemented as *any* `keyDown`. The policy itself worked —
AppKit controls switched to `.none` on a click and back to `.default` on a key.
But main had just gained the plain-text editor, where typing is constant, and
`⇧⌘E`. A single letter or shortcut set the global flag, restored every ring,
and left it there until the next click. Pure mouse users then saw rings
"everywhere", and the earlier fix was suspected of having been lost in a
rebase.

`971e244` narrowed the check to the keys that actually move focus (key code
48, Tab and its variants). The runtime check that found it was reading
`isKeyboardActive` on a live instance, not looking at the diff.

**Rule.** A fix is verified only when the failing action has been performed
before the fix (fails) and after it (passes). "It builds", "the code path
runs", and "the setting is applied" are not verification of a user-visible
behaviour.

### 1.2 The root cause was asserted from a theory

The first explanation for the regression was "the rebase dropped the fix".
`git range-diff` showed the three commits replayed byte for byte, and the
running app still had the policy applied. The theory cost a diagnosis cycle
and, worse, would have produced a "fix" that changed nothing.

**Rule.** Do not merge a fix whose commit message names a cause that was not
demonstrated. Put the evidence in the PR: the reproduced failure, the
instrumented state or the comparison that rules the other causes out. If the
cause is still unknown, say that explicitly instead of shipping a plausible
change.

### 1.3 The verification matrix was too narrow

The focus-ring work changes global input state, but it was checked with a
build and a look at the settings pane. The interactions that mattered were the
ones added around it: typing in the editor, shortcuts, scrolling keys, and
opening a window with a keyboard shortcut.

**Rule.** For input, focus, keyboard, and rendering changes, verify the whole
matrix on the base that will be merged:

| Input | Expected |
| --- | --- |
| mouse click | rings hidden |
| Tab / Shift-Tab | rings shown |
| typing in the editor | no change |
| command shortcut | no change |
| scrolling keys | no change |
| new window / popover / sheet | starts hidden, Tab shows |

Record the result in the PR. A matrix that is not written down is a matrix
that was not run.

### 1.4 User-facing strings shipped in some languages only

The feature commit added the new strings to `en` and `zh-Hans`. German arrived
in a follow-up commit (`62b9b9e`). Japanese, Polish and Persian never got the
oversized-document placeholder; those readers saw English until this cleanup
added it. The share viewer had a test for its strings; the app did not.

**Rule.** All `.lproj` files change in the same commit as the English string.
`scripts/check-localizations.py` now compares keys and format specifiers for
every language and runs in CI. A translation that drops `%@` or renumbers
`%1$@` is also a build-breaking defect, not a wording preference.

### 1.5 Warnings and build scripts were left for later

`494d731` removed compiler warnings after the feature work, and `ef6b51d` /
`1bbfebe` repaired a build script written with zsh assumptions. Both are
follow-ups to work that was already called complete. A build that warns hides
the next warning; a script that only ran in the author's shell is not a
script.

**Rule.** A change leaves the build warning-free and the scripts runnable in
their declared shell. If a warning cannot be fixed in the change, the PR says
which one and why.

### 1.6 Documentation drifted from the code

`docs/diagram-sizing.md` still said "Nothing implemented" after the feature
shipped, and the ticket still said "ready for implementation". The focus-ring
behaviour was documented only after four fix commits. The repository has
already paid for this pattern once: a stale README claim about Mermaid in
Quick Look made a real regression look like documentation drift (#338, fixed
in #343).

**Rule.** When the change makes a documented claim false, the same commit
updates the claim. Historical discussion notes get a status line that says
they are historical, not a silent rewrite.

### 1.7 Agent tooling polluted the repository

The working copy had 171 `refs/waku/session-*` snapshot refs (103 snapshot
commits). They were local only, but they made `git log --all` and
`git branch -a` unreadable for every later review. They were removed during
this cleanup; the mapping was saved to `.git/waku-refs-backup.txt` before
deletion.

**Rule.** Agent and editor tooling must not create refs, commits or untracked
files in the user's repository. If it does, remove them before handing the
work back, and do not run `git log --all` in a review while they exist.

### 1.8 Large and boundary inputs were not tested

A 40 MB table-heavy document hung the app for 11 s and reached 4 GB, because
the renderer and the outline each built a CommonMark tree. The fix added a
5 MB limit and a placeholder (`DocumentSizePolicy`), but only after the
failure reached a user.

**Rule.** For a parser, renderer, or list view, test the boundary before the
PR: an empty input, a normal input, and an input above the documented limit.
State the limit in the PR.

### 1.9 Mechanical refactors and behaviour changes were mixed

`82ccc62` fixed three different problems in one commit: the outline parsed the
document a second time, documents above 5 MB had no limit, and the highlight
pass copied a `[Character]` array it usually did not need. Each change is
good, but a reviewer cannot tell which edit caused a regression, and a
`git bisect` lands on all three at once.

**Rule.** A commit does one thing. A move or rename lands on its own (the CLI
installer extraction in this cleanup, for example), before or after the
behaviour change, so its diff can be read as "the same code in a new place".

## 2. What should not have been merged

Each item is a concrete merge that should have been blocked or changed:

- a focus fix whose verification was a successful build (1.1, 1.3);
- a diagnosis that blamed the rebase without `range-diff` (1.2);
- an English-only user-facing string with a promised translation follow-up
  (1.4);
- a feature commit that left new compiler warnings and a shell-specific build
  script (1.5);
- a discussion note and a ticket whose status contradicted the shipped code
  (1.6);
- local tooling refs left in the repository (1.7);
- a renderer limit discovered by a user instead of a boundary test (1.8);
- a commit that mixes a mechanical refactor with a behaviour change, so
  neither can be reviewed or bisected on its own (1.9).

## 3. Gates now in place

- `python3 scripts/check-localizations.py` — key and format-specifier parity
  for every `.lproj`; runs in `swift-tests.yml`.
- `ShareViewerKitTests` — regenerates and verifies the share viewer's
  `generated/*` assets, so they cannot drift from the Swift renderer.
- The existing Swift test suite and the performance workflow.
- The pre-merge checklist in `AGENTS.md`, which turns the rules above into
  steps an agent has to perform.
