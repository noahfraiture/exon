# Maintaining the native mode

Upstream base: Neovim 0.13 development,
`0851e7dabed9fc9c019e22088029f36e9f3ec3e3`.
This is a pinned development snapshot, not an upstream 0.13 stable release.
Exon development uses the default `master` branch. The old `helix` branch is
retained as a compatibility snapshot for existing inputs; keep its history.
The GitHub repository remains a fork of `neovim/neovim`. Use the `upstream`
remote for Neovim updates: `origin/master` contains Exon, while
`upstream/master` tracks Neovim development.

## Boundaries

* `src/nvim/helix.c` owns native mode/selection semantics and per-window Context
  collections. Optional Context range metadata uses native extmark tracking.
* On insertion entry, secondary Context ownership transfers to upstream
  `mcursor.c`; on exit it transfers back. There is one active cursor collection,
  with upstream command entry, input, indentation, preview/replay and completion.
* `insert.c` and `insexpand.c` are upstream source. Do not restore the old Lua
  insertion interpreter or primary-only completion hooks.
* `src/nvim/api/helix.c` provides additive selection/transaction APIs. Explicit
  cursor jumps in Helix normal mode retain their primary-cursor contract.
* Bundled Lua implements selection policy and thin native range adapters for
  indentation/joining. `contrib/helix/init.lua` is optional configuration.
* `vim.helix.defaults` owns shared editor bindings and their descriptions.
  Both default mappings and the raw-key dispatcher use the same actions; do
  not add basic diagnostics/navigation only to the example config.
* `vim.helix.compat` owns explicit, version-tested plugin adapters. Keep mode
  reporting truthful and run `contrib/helix/plugin-smoke.lua` with the pinned
  `plugins.json` revisions when changing input, mappings or those adapters.
* Native text undo owns history; Helix adds session-local oriented selection
  metadata. Native Insert cursor movements keep upstream undo boundaries.
* Mouse geometry and scrolling remain in upstream `mouse.c`. Two adapters adopt
  completed selections and synchronize a wheel-clamped primary cursor; preserve
  the hovered-window scope and secondary selections when updating this code.

The rebase hotspots are normal/input dispatch, Context range tracking and
ownership transfer, explicit cursor entry points, undo metadata, and lifecycle
cleanup. The ownership helpers are internal adapters, not a public competing
multicursor backend. See [REVIEW.md](REVIEW.md) for product examples and limits.

The built-in snippet adapter enters Vim Select mode for placeholders. Native
completion keeps compatible cursors, using the primary candidate. This does not
promise independent per-cursor LSP requests or snippet placeholder groups.

Selection metadata is not serialized into undo files. Do not change the native
undo-file format incidentally. Dot-repeat/macro parity is optional future scope.

## Updating upstream

A fresh clone can configure the upstream remote explicitly:

```sh
git remote add upstream https://github.com/neovim/neovim.git
git fetch upstream
```


1. Make a branch/tag at the current tested Helix revision. Preserve a working
   binary/runtime pair and configuration so an update can be rolled back.
2. Fetch the desired upstream release and read its breaking changes. Use a
   separate worktree for the upgrade. Merge it normally, or rebase only the
   current native adapter and its follow-ups as described below.
3. Review every conflict in the integration points above. Re-run code generation;
   never resolve generated API/options metadata by hand.
4. Keep upstream's API level/prerelease policy. Helix methods use the current
   experimental level, above the latest frozen fixture. Do not mark an upstream
   development level stable just to give fork methods a higher number. Detect
   fork capabilities by API names or `exists('+helix')`.
5. Run native Helix tests, the editor/API suites, snippet/completion tests, UI
   coverage and a sanitizer build. Test the example configuration as shipped.
6. Test the exact plugin/parser revisions used in the distribution. Upgrade those
   independently from core so a failure has an identifiable source.
7. Record the new upstream base here and release the matching executable/runtime.

The 0.13 migration records the exact upstream tree in merge commit
`27c2c3d0f44375c95edcc039df4b809fa1cac870`, followed by a separate native adapter
commit. This preserves the published history without replaying the retired
0.12 implementation. To rebase the current patch series explicitly:

```sh
git switch -c upgrade-helix master
git rebase --onto <new-upstream> 27c2c3d0f44375c95edcc039df4b809fa1cac870
```

Do not use an unqualified rebase that would also replay the legacy 0.12 commits.
A normal upstream merge remains supported; review the resulting fork delta.
After any history rewrite, verify in an isolated branch before publishing.

## Acceptance gates

* Feature disabled: ordinary Vim editing and APIs retain their behavior.
* Feature enabled: `mode()` reports `h`/`hv`, insertion reports native `i`, and
  normal Vim mappings are not expanded before Helix commands.
* `mim`, `ma/`, repeated word motions, counts, direction and graphemes work.
* Multiple selections can be edited together; native undo/redo restores text,
  primary selection and direction, including alternate undo branches.
* External API edits transform selections; explicit cursor jumps have a defined
  primary-cursor effect. A second window does not share selection state.
* Insert events/mappings, completion, snippet placeholders, streamed paste,
  buffer destruction and disable/re-enable behavior remain predictable.

## Publishing a preview

Dispatch the `Native Helix` workflow on `master` with a new `release_tag`, such as
`helix-preview-0.1.0`. Leave the input empty to run checks without publishing.
Publication requires both platform jobs and the sanitizer job to succeed. The
release uses that same run's archives and source commit, with checksums and the
notes in `contrib/helix/RELEASE.md`. Existing release tags are not overwritten.

## Nix packaging

`flake.nix` reuses the Neovim recipe and remote-plugin integration from the
Nixpkgs revision in `flake.lock`; it substitutes this fork's source and adds
Helix functional/installed smoke checks. `Native Helix Nix` checks Linux x86-64
and macOS ARM64. The other exported systems are evaluated, not native-built in
that workflow. Keep the `lua` and parser attributes so NixOS/Home Manager can
wrap the package normally. Parser sources come directly from the pinned
upstream `cmake.deps/deps.txt`, through `treesitter-parsers.nix`. After changing the upstream base or Nixpkgs lock,
recheck the recipe's patches, dependencies and parser versions and run
`nix flake check`. The locked wrapper expects `nvim.desktop`; the package
renames upstream 0.13's desktop file on Linux. Remove that compatibility rename
when upgrading to a recipe that handles the new name. See [NIX.md](NIX.md) for the input/package interface.

## Licensing

The command calculations originated in `noahfraiture/helix.vim` under MIT.
Its notice is retained in `LICENSE-helix.vim`. Neovim's existing licenses and
third-party notices remain in force for their respective code.
Official bundles include these notices and the matching application/dependency
source. See [DISTRIBUTION.md](DISTRIBUTION.md). Packaging requires a clean tracked
tree and the default bundled dependency build; retain the source when
redistributing binaries, including statically linked LGPL components.
