# Verification record

Current migration base: Neovim 0.13 development,
`0851e7dabed9fc9c019e22088029f36e9f3ec3e3`.

The 0.13 suite adds native indented o/O and I/A at multiple cursors, deduplicated
selected-line indentation with counts/undo, disjoint joins with native whitespace
rules, native Context ownership during insertion, and completion after changing
differently sized surrounds on one line. Native Insert controls now retain all
cursors. Arrow/mapping undo boundaries are compared with an ordinary upstream
multicursor control. Old primary-only fallback expectations have been replaced
with assertions that all compatible cursors participate.

Local Linux Debug verification for this migration (2026-10-18):

* Editor suite, including 87 Helix tests: 826 passed, 5 skipped.
* API compatibility: 1,481 passed, 5 skipped.
* Built-in snippets: 35 passed; built-in LSP completion: 56 passed.
* The Helix suite includes an actual built-in LSP completion session, native
  context ownership, and returning from Insert after a buffer/window switch.
* Generated help/API metadata, C/Lua formatting and focused C lint passed.
* Installed `exon`, `ex` and `nvim` passed the example-configuration smoke check.

Nix grammar sources are derived from upstream's pinned dependency manifest,
so the installed runtime and grammars use the same revisions as bundled builds.
The counts/platform results below are historical baselines; current workflow
logs and installed smoke checks cover the exact source being published.

Initial verification baseline: `acfe165` (Neovim v0.12.6 base), 2026-10-16.
Preview notes link the passing workflow for their exact source commit. Every
preview repeats the platform, integration and sanitizer gates below.

Preview 0.1.3 adds distribution notices and matching source to each bundle.
Its installed-package check also requires the license/source files and verifies
that version output identifies the executable as a Helix preview. This fixes
packaging omissions; it does not expand the editor's compatibility guarantees.
The macOS package also checks executable/parser dynamic-library paths and
rejects dependencies outside macOS system directories. Its build follows the
upstream release flags to avoid relying on the runner's Homebrew gettext.

Preview 0.1.1 adds optional setup, key overrides, configurable surround pairs
and a direct surround helper. Six additional functional tests cover defaults,
string/callback/disabled mappings, custom pairs at multiple cursors with undo,
nested and symmetric markers, Unicode, configuration validation and repeated
setup. The installed-package smoke test also exercises setup and a custom pair.
The baseline counts below describe the initial build; each preview's workflow
logs contain its current counts. These historical baseline results used the 0.12.6 engine.

The follow-up architecture review adds regressions for literal command
arguments under mappings, native Alt shortcuts, Insert cursor placement and
empty-line cursor preservation, native-control fallback/undo, Unicode case
conversion, parser cancellation and special delimiter keys. The dedicated
suite now contains 87 tests, including native Unicode word classes and
'iskeyword'. A colorscheme-reload control also passes without
a production change. See [REVIEW.md](REVIEW.md) for the feature inventory and
the architectural work still required; passing these tests does not establish
complete Helix parity.

Word-boundary regressions cover the reported backward selection from `saf`
to `sadf `, including the actual screen highlight and change/undo behavior.
The same checks cover forward word ends, direction changes, counts, explicit
selection extension, WORD motions, punctuation, Unicode graphemes, indentation,
blank lines and multicursor edits. The backward/forward boundary and screen
tests failed before the fix; they verify that the old cursor character does
not remain in the replacement selection. The installed-package smoke test also
checks the reported backward selection, replacement and undo through real input.

Surround replacement/deletion regressions cover `mr"'`, `md`, nearest pairs,
counts and bracket aliases; literal command arguments under mappings; custom
multi-character and Unicode pairs; shared and nested surrounds; empty and
multiline content; escaped delimiters; native marks inside the retained text;
screen highlighting, selection direction and primary index; undo/redo;
cancellation and missing/conflicting pairs. A 5,001-cursor test verifies that
more than 10,000 delimiter edits retain their coordinates across native batches
and undo in one step. Installed-package checks also exercise replacement and
deletion with built-in and configured pairs at multiple cursors.

The [Native Helix workflow run](https://github.com/noahfraiture/exon/actions/runs/38859243012)
passed every job. It built the executable and matching runtime from this source.
Preview releases link their own passing workflow and publish that run's exact
packages. Follow-up work adds documentation, release automation and mode
reporting inside native mapping callbacks.

| Check | Linux x86-64, Ubuntu 24.04, Clang | macOS ARM64, macOS 14, Clang |
| --- | --- | --- |
| Build, RelWithDebInfo | Pass | Pass |
| Editor suite, including 31 native Helix tests | 529 passed, 5 skipped | 531 passed, 4 skipped |
| API compatibility suite | 1,371 passed, 3 skipped | 1,371 passed, 3 skipped |
| Built-in snippets | 34 passed | 34 passed |
| Built-in LSP completion | 45 passed | 45 passed |
| Installed binary, bundled runtime and example configuration | Pass | Pass |

The separate Linux address/undefined-behavior sanitizer job passed all 31 native
Helix tests. Leak detection was enabled. Platform/build-dependent upstream skips
remain visible in the workflow logs; a skipped test is not counted as passed.

Additional local verification on Linux with GCC 14.2, Debug:

* Editor suite: 531 passed, 4 skipped.
* API suite: 1,371 passed, 3 skipped.
* Entire Lua suite: 1,222 passed, 24 skipped, including the snippet tests above.
* LSP completion: 45 passed.
* Address/undefined-behavior sanitizers: all 31 Helix tests passed with leak
  detection enabled.
* An independently installed local package passed its smoke test.
* Both CI archive checksums were verified after download. The extracted Linux
  CI archive passed its smoke test again outside the build tree.

The first local Lua run found the second sanitizer executable while testing
filesystem traversal. Renaming that extra executable out of the fixture's
search removed the interference; the full Lua suite then passed. No upstream
test expectations were changed.

## What the native tests exercise

Real Neovim input, mode reporting and screen output; ordinary Vim behavior when
disabled; independent `h` mappings (including callback mode reporting and
explicit Visual-mode entry); repeated word motions; `mim` and `ma/`;
selection extension; simultaneous changes; primary index and direction through
native undo/redo and alternate undo branches; window/buffer ownership; external
buffer edits and cursor jumps; Unicode graphemes including ZWJ emoji; real
Insert events/mappings and `InsertCharPre`; native completion's primary-cursor
fallback; built-in snippet placeholders; autoindent; streamed and prompt paste;
search; per-selection registers; undo-file compatibility; buffer destruction;
and the shipped configuration's buffer navigation.

## Scope of the result

This verifies an initial native implementation, not complete Helix parity or
every third-party plugin. The upstream regression suites primarily verify that
ordinary Neovim remains intact with the feature disabled. The dedicated Helix
tests cover enabled-mode integration.

Completion has one primary context. Built-in snippet placeholders enter Vim
Select mode. External snippet/completion plugins, macro/dot-repeat parity,
syntax-aware textobjects, full mouse behavior, advanced multicursor indentation
and very-large-file performance remain work to do. See [HELIX.md](../../HELIX.md)
for the user-facing boundaries and the small manual acceptance test.

## Reproduce installed-package checks

A local Linux x86-64 Nix source build passed its parser checks, all 47 Helix
tests, version validation and installed configuration smoke test.

For the source-built Nix package, `nix flake check` runs the locked Nixpkgs
parser checks, the dedicated Helix suite and an installed configuration smoke
test. Nix packages retain the root/MIT notices and use dependencies from the
locked derivations; the separate download-archive license/source layout is
checked only for release archives. The `Native Helix Nix` workflow builds Linux
x86-64 and macOS ARM64 and evaluates all three exported systems.

After extracting a preview archive, change into its top-level directory:

```sh
./bin/nvim --headless -i NONE -u NONE \
  -l ./share/neovim-helix/smoke.lua \
  "$PWD/bin/nvim" "$PWD/share/neovim-helix/init.lua"
```

This launches a separate RPC child with temporary configuration/data/state/cache
directories. It checks mode activation, `mim`, change/undo and multicursor
change/undo with restored selections. It prints `PASS` or exits with an error.
It does not load or change your personal configuration.
