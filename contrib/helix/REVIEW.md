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

## Everyday editor contract

The baseline is Helix selection-first editing with Neovim's ordinary editor
services and explicitly supported plugins. Enable it with only `set helix` or
`vim.o.helix = true`. The example init file is not required to repair the mode.

| Workflow | Owner and acceptance check |
| --- | --- |
| Motions, selection direction, multiple selections, insert/change/delete | Native selections and bundled selection commands; real input, Unicode, window ownership and undo tests |
| Paste and clipboard | Helix's newline-content rule and Neovim providers; linewise/inline, named registers, external changes and multicursor tests |
| Undo/redo and indentation | Native history and insertion; comparison with ordinary Neovim, selection restoration and shared-line indentation tests |
| Mouse, wheel, scrolling, centering and scroll margins | Neovim geometry; attached-screen tests including wrapped lines, folds, splits and secondary selections |
| Diagnostics | `[d`, `]d`, `[D`, `]D` call `vim.diagnostic.jump`; counts, wrap, configured feedback and native jump history are tested without an LSP or example config |
| Language navigation and actions | `gd`, `gD`, `gy`, `gr`, `gi`, Space k/r/a call the existing LSP APIs at the primary cursor; a configured server still supplies language support |
| Formatting | `=` passes oriented selections to Neovim's formatting API; file formatting remains an ordinary configurable action |
| Files, buffers and jumps | `gf`, `gn`, `gp`, `ga`, Ctrl-o/Ctrl-i use native file/buffer/jumplist commands; personal picker shortcuts stay configurable |
| Plugin windows | Pickers and other special buffers use normal Neovim modes, then return to the document's Helix mode |
| Known plugins | Pinned which-key, Telescope, ui-select and Flash run together in an attached UI; quick/slow shortcuts, h/hv cancellation, picking and diagnostics are exercised |
| Ordinary Neovim | Disabling Helix retains n/x/i mappings and native behavior; normal-mode editing mappings never implicitly become Helix commands |

Diagnostic jumps and other external cursor jumps intentionally replace the
selection collection with a primary cursor. View-only commands preserve the
collection. This distinction is part of the contract, rather than a guess by
each plugin. Native jump history restores positions, not a Helix selection stack.

Default shared actions live in `runtime/lua/vim/helix/defaults.lua` and are
installed during runtime initialization. Their mappings have descriptions for
discovery tools. The input adapter uses the same table after a prefix timeout
or nonrecursive mapping, consumes counts once, and cancels unknown prefixes
without executing the trailing key as an editing command. User maps can override
defaults. Space f stays available for personal file picker prefixes; formatting
uses `=`.

## Mapping and plugin policy

Keep the real h/hv modes: exposing them as Vim normal mode would make plugin
assumptions and selection semantics disagree. Existing n maps remain n maps;
configure a shared action with `vim.keymap.set({'n', 'h'}, ...)` when appropriate.
Do not copy arbitrary normal-mode editing mappings or fall through to Vim
operators for unknown Helix commands.

Exon owns small, explicit adapters for supported plugins in `vim.helix.compat`.
For which-key, pass ordinary options through
`vim.helix.compat.which_key(options)` before its setup. This handles mode
recognition, h/hv transitions and h triggers, without loading the plugin unless
requested. User configuration owns its preferred groups, appearance and delays.
Flash and Telescope use ordinary h mappings and need no internal adapter for the
tested workflows. Syntax-node selection still requires the matching parser.

`contrib/helix/plugins.json` pins the tested plugin revisions. Run
`exon --headless -u NONE -i NONE -l contrib/helix/plugin-smoke.lua` to fetch those
pins into a temporary directory and test the workflows. An optional directory
argument uses existing checkouts offline and verifies their revisions. CI runs
this alongside the native/editor/API/completion suites on Linux and macOS.

These gates establish the listed baseline, not complete Helix parity or
compatibility with arbitrary plugins. New features and upstream upgrades must
preserve these workflows, not just pass a test for the newly changed command.

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
