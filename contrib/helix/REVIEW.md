# Architecture and feature review

Current upstream base: Neovim 0.13 development,
`0851e7dabed9fc9c019e22088029f36e9f3ec3e3` (2026-10-18).

## Product boundary

`vim.helix.setup()` enables selection-first editing with useful defaults. Users
can change keys and surround pairs; they do not need mappings to repair normal
editing. The baseline includes word/line selection, `mim`/`ma/`, surround
add/replace/delete, multicursor changes, native indented `o`/`O`, `I`/`A`,
selected-line `>`/`<`, `J`, compatible completion, and selection-preserving undo.
Dot-repeat and macro parity are optional future scope. They do not block this
baseline. Pickers, buffer management, Git, UI preferences and language providers
remain ordinary Neovim configuration/plugins.

## Ownership and reuse

* Helix owns its real `h`/`hv` mode, mapping namespace and half-open selection
  semantics. The primary selection and direction remain explicit.
* Selections use upstream `Context` objects, with optional tracked range metadata.
  Their positions are not mirrored in a second cursor collection.
* During insertion, secondary Context ownership transfers into upstream
  `mcursor.c`. Native command entry, input, preview/replay, mappings, controls,
  indentation and completion execute there. On exit, the same contexts return
  to the window's Helix selection collection. Dormant windows keep independent
  collections. There is no Lua insertion interpreter.
* `insert.c` and `insexpand.c` remain upstream source. The 0.12 insertion and
  completion-collapse hooks have been removed.
* Bundled Lua calculates selection commands and simultaneous delimiter edits.
  `>`/`<` and `J` are small range adapters over native Ex operations. Shared
  lines are processed once; disjoint changes join the same undo block.
* Native text undo remains authoritative. Session-local Helix selection
  snapshots add range orientation/primary identity; the undo-file format is
  unchanged. Insert cursor movements keep native Neovim undo boundaries.

The Context/mcursor ownership helpers are internal, not a new public cursor
framework. The public selection/edit APIs remain additive and experimental at upstream's
prerelease API level 15. Detect their names (or the helix option), not a separate
fork API-level bump; upstream level 15 is not frozen yet.

## Acceptance examples

The functional suite drives actual input, API state, edits, undo and screen
highlights. In particular it covers:

* `saf` selected backward, then `b`: select `sadf ` without retaining the old `s`.
* `mr"'`/`md"`: change/remove only the delimiters, retaining the selected content,
  direction, primary cursor and marks inside the text.
* Two differently indented lines, `oX<Esc>`/`OX<Esc>`: each uses its own native
  indentation and one undo restores the pre-entry selections.
* Several selections sharing a line, plus a disjoint line, `>`: shift each line
  once, using `shiftwidth`/`expandtab`; one undo restores all ranges.
* Disjoint selected lines, `J`: join with native whitespace rules and undo the
  whole operation.
* `(a) (longer)`, select both interiors, change and complete `he` to `hello`:
  produce `(hello) (hello)`, retain both cursors, undo to both original interiors.
* Insert mappings, arrows, deletion and newline: text and undo stages match an
  ordinary 0.13 native-multicursor control.

The editor suite also runs upstream multicursor/command-capture tests with
Helix disabled. API, snippet, LSP completion, sanitizer and installed-package
checks provide separate compatibility coverage; the workflow logs identify the
exact tested commit and platform.

## Remaining limits

Completion uses the primary candidate at compatible locations. Independent
per-cursor LSP requests, arbitrary additional edits and multicursor snippet
placeholder groups are not guaranteed. Built-in single-context snippet workflows
are tested; other completion/snippet plugins need their own workflow tests.

Full mouse parity, syntax-aware textobjects, complete Helix command coverage,
and macro/dot-repeat parity remain outside this baseline. The command layer
still reads a temporary document snapshot, so large-file scaling needs more
work. Persistent undo saves text, but not extra Helix selection metadata.

Basic mouse input is covered: click placement, character/line selection on
release, vertical/horizontal wheels, inactive-window scrolling, mapping
overrides and native Insert clicks. Blockwise mouse selections keep Vim Visual
behavior; no custom mouse geometry or scrolling implementation is maintained.

The fork still has rebase-sensitive integration points: native mode dispatch,
Context range tracking/ownership transfer, cursor API boundaries, and selection
undo metadata. Keep these adapters small and rerun the product examples after
upstream changes. Passing tests cover those workflows; they do not certify
arbitrary third-party editing plugins or complete Helix parity.
