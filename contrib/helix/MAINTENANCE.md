# Maintaining the native mode

Upstream base: Neovim v0.12.6, `779c36969e31080503be2dfccbcc3f999e289606`.
The native feature branch is `helix`; `master` remains available for upstream.

Upstream 0.13 already has native multicursors ([merged implementation](https://github.com/neovim/neovim/pull/41587)).
The 0.12 bridge is a preview, not the intended long-term multicursor backend.
Prioritize integration with upstream contexts, insertion, completion and repeat
before expanding the legacy engine. See [REVIEW.md](REVIEW.md) for the feature
inventory, reproduced defects and acceptance criteria for that migration.

## Boundaries

* `src/nvim/helix.c` owns window/buffer selection collections, mark tracking,
  normalization, rendering, transactions and selection undo snapshots.
* `src/nvim/api/helix.c` exposes additive selection APIs. Existing cursor APIs
  retain their single-primary contract.
* `runtime/lua/vim/helix.lua` and `helix/commands.lua` implement command policy
  over transient snapshots. There is no independent document or undo history.
* `contrib/helix/init.lua` is an optional configuration, not core policy.

Core connections are concentrated in state/mapping dispatch (including command
arguments and Alt-key normalization in `getchar.c`), native Insert
mode, undo header lifecycle, cursor entry points and window/buffer cleanup.
These are the rebase hotspots. Keep their changes small; do not fork copies of
the upstream insertion, mapping or undo implementations.

The built-in snippet adapter explicitly enters Vim Visual/Select mode for
placeholders. Native completion collapses to its one primary context. These
choices preserve conventional plugin contracts while vector editing remains
available through explicit selection transactions.

Selection metadata is not serialized into undo files. Changing this later
requires an explicit optional-field/version design and old-file tests. Do not
change the existing undo file format incidentally.

## Updating upstream

1. Make a branch/tag at the current tested Helix revision. Preserve a working
   binary/runtime pair and configuration so an update can be rolled back.
2. Fetch the desired upstream release, read its breaking changes, and rebase the
   Helix commits onto it. Use a separate worktree for the upgrade.
3. Review every conflict in the integration points above. Re-run code generation;
   never resolve generated API/options metadata by hand.
4. Check upstream's current API level. The fork's extension level must remain
   experimental and above the most recent frozen upstream API fixture. Update
   the extension methods' `FUNC_API_SINCE` values when necessary.
5. Run native Helix tests, the editor/API suites, snippet/completion tests, UI
   coverage and a sanitizer build. Test the example configuration as shipped.
6. Test the exact plugin/parser revisions used in the distribution. Upgrade those
   independently from core so a failure has an identifiable source.
7. Record the new upstream base here and release the matching executable/runtime.

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

Dispatch the `Native Helix` workflow on `helix` with a new `release_tag`, such as
`helix-preview-0.1.0`. Leave the input empty to run checks without publishing.
Publication requires both platform jobs and the sanitizer job to succeed. The
release uses that same run's archives and source commit, with checksums and the
notes in `contrib/helix/RELEASE.md`. Existing release tags are not overwritten.

## Licensing

The command calculations originated in `noahfraiture/helix.vim` under MIT.
Its notice is retained in `LICENSE-helix.vim`. Neovim's existing licenses and
third-party notices remain in force for their respective code.
Official bundles include these notices and the matching application/dependency
source. See [DISTRIBUTION.md](DISTRIBUTION.md). Packaging requires a clean tracked
tree and the default bundled dependency build; retain the source when
redistributing binaries, including statically linked LGPL components.
