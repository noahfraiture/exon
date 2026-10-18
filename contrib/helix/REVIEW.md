# Architecture and feature review

Review baseline: preview 0.1.1, `76719da5e7d47c09b53c6497f24c8a80dea75ad5`.
Date: 2026-10-16. Fixes described below are in the follow-up preview.

## Conclusion

The fork provides a real opt-in selection-first mode and the requested `mim`,
`ma/`, `x` and multicursor editing workflows. It is not complete Helix parity,
and its current 0.12 multicursor bridge is not the best long-term maintenance
boundary. Upstream 0.13 already owns multicursor insertion, completion and repeat.
The next architectural milestone should reuse those facilities before adding
more special cases to this bridge.

This review combined source inspection, failing input-driven regressions,
ordinary-Neovim controls, a theme-reload control and small performance probes.
Passing tests protect the exercised contracts; they do not certify all plugins
or all Helix commands.

## Reproduced defects corrected

| Trigger in 0.1.1 | Result after the fix |
| --- | --- |
| Remap `i`, `w` or a delimiter, then use `miw`/`ms(` | Command arguments bypass the top-level mapping table; user mappings remain available outside arguments. |
| Use an Alt command such as Alt-C or Alt-backtick | Helix receives the modifier instead of Escape followed by the unmodified key. Ordinary Vim retains its existing behavior. |
| `i<Right><Right><Right>X<Esc>` in `hello` | Selection follows native Insert's actual cursor and selects `X`. |
| Enter/leave Insert on two empty lines | Cursors at column zero stay on their own lines instead of crossing the newline and merging. |
| Use a non-vectorized Insert control after typing at several cursors | The command continues in one native context instead of silently diverging cursor state. Ctrl-D keeps native indentation semantics. This is a safe fallback, not full support at every cursor. |
| Lowercase/uppercase/toggle accented or Greek text | Commands use Neovim's Unicode conversion rather than Lua's byte-oriented ASCII conversion. |
| Move/select words around Unicode punctuation or customize 'iskeyword' | Commands reuse Neovim's character classes; emoji are distinct from newline boundaries. |
| Type `ms<F1>` | A special key name is not inserted into the document as a delimiter. |

Regressions also check that pending arguments are canceled across configuration
and buffer changes. Reloading the default colorscheme already preserved the
default highlight links; that control needed no production change.

## Simplifications

* Remove unused Lua history limits, snapshots, checkpoint calls and history
  branches. Native undo remains the sole history owner.
* Compute/merge edit ranges once. The command layer emits its validated plan to
  the adapter before updating its temporary model; the adapter no longer repeats
  the planning algorithm. Core still independently validates edits before writes.
* Reuse native case conversion, word classes and the native Insert cursor. Avoid
  adding another Unicode table or cursor-motion implementation.
* Obtain pending-argument state from the existing parser, rather than maintain a
  second pending-state flag with separate lifecycle rules in C.

## Feature inventory

| Area | Current boundary |
| --- | --- |
| Opt-in `h`/`hv` mode and mapping namespace | Implemented; default remains ordinary Vim. |
| Oriented selections, primary selection, tracking through edits | Implemented in core, per window/buffer. |
| `mim`, `ma/`, word/line objects, configured surrounds, `mr`/`md` | Implemented as lexical commands in bundled Lua. |
| Multicursor change/delete/yank/paste and selection undo/redo | Implemented for the supported commands, using native text undo. |
| Insert typing, deletion, arrows, tabs, newline/basic autoindent | Implemented for the vectorized set; other native Insert commands keep one primary context. |
| Completion and built-in snippet placeholders | One context. Full multicursor completion/snippet groups are not implemented. |
| Search and match selection/splitting | Implemented with Vim regex syntax. |
| Unicode selection and case operations | Native grapheme boundaries and native case conversion; exercised by regressions. |
| `o`/`O` indentation | Incomplete: lines are opened without native open-line indentation. |
| Macro/dot-repeat parity | Not implemented for Helix commands. |
| Syntax-aware objects, full mouse parity | Not implemented. |
| Third-party editing plugins | Require workflow validation; loading a plugin is not sufficient evidence. |
| Selection metadata across editor restarts | Not persisted; native text undo-file format remains unchanged. |

## Performance and remaining risks

The command adapter still reads the complete buffer for each key. In one local
GCC Debug build, 30 direct word-motion policy calls averaged about 0.09 ms at
0.1 MiB, 0.32 ms at 1 MiB and 5.20 ms at 9.5 MiB. This excludes UI/input overhead
and is not a cross-platform performance guarantee. The scaling follows from the
whole-buffer snapshot, so larger-file performance remains work to do.

The most consequential maintenance risk is duplicated upstream responsibility:
the legacy bridge owns cursor collections, insertion dispatch and undo selection
metadata separately from 0.13's multicursor contexts. Its rebase hotspots include
normal/input dispatch, Insert/completion, cursor entry points, undo lifecycle and
window/buffer cleanup. A small textual patch alone does not prove those contracts
remain compatible after rebasing.

Rollback remains straightforward: `:set nohelix` restores ordinary Vim editing.
There is no document-format migration or changed undo-file serialization.

## 0.13 acceptance criteria

Investigated upstream snapshot: `be5167e21cfbb5d566c09a67c1852d0e18c62c38`.
Its native multicursor engine already stores cursor contexts/Visual state and
cascades semantic commands. Integration is not achieved by merely retaining both
engines after rebasing.

1. One authoritative cursor/selection collection, with upstream insertion,
   completion, registers, undo and repeat wherever their contracts fit.
2. Keep the native Helix mode/selection contract and the small public Lua
   configuration/command interface. Delete replaced bridge paths rather than
   leave an alternative backend to maintain.
3. Demonstrate `mim -> change -> completion -> Escape -> undo` across differently
   sized selections, including cursors on the same line.
4. Verify argument mappings, modifier keys, empty lines, external edits, window
   changes, Unicode, undo branches and ordinary Vim mode.
5. Exercise actual completion/snippet plugin workflows before claiming their
   compatibility. Preserve an independently usable binary/runtime for rollback.
