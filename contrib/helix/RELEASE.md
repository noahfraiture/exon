Exon adds opt-in native selection-first editing to Neovim 0.13 development.
Enable the defaults with:

```lua
vim.helix.setup()
```

This preview reuses upstream multicursor insertion and completion. It removes
the 0.12 Lua insertion interpreter and primary-only completion fallback. Compatible
completion retains all cursors. Native o/O and I/A provide indentation; >/<
indent selected lines once, and J joins them using native whitespace rules.
Surround selection/add/replace/delete, including mim, ma/ and mr"', remain built in.

Ordinary Vim editing is the default until the mode is enabled. Keybindings and
surround pairs are optional configuration. The upstream development revision is
pinned in MAINTENANCE.md; this is not an official Neovim 0.13 stable release.

Download and extract the matching platform archive. Keep bin and share together:

```sh
./neovim-helix-Linux-X64/bin/exon -i NONE \
  -u ./neovim-helix-Linux-X64/share/neovim-helix/init.lua
```

For macOS Apple Silicon, use the macOS-ARM64 archive. exon, ex and nvim are names
for the same executable and use your existing Neovim configuration. Remove an
old require('helix').setup() plugin configuration when adopting the fork.

Each archive includes license notices, matching source/dependency archives,
SOURCE_COMMIT and a checksum. The release is produced only after its native
Linux/macOS, API, snippet, completion, installed-package and sanitizer jobs pass.
Nix builds/checks the same native mode and matching parser revisions.

[Instructions](https://github.com/noahfraiture/exon/blob/master/HELIX.md)
· [Nix](https://github.com/noahfraiture/exon/blob/master/contrib/helix/NIX.md)
· [Feature review](https://github.com/noahfraiture/exon/blob/master/contrib/helix/REVIEW.md)
· [Verification](https://github.com/noahfraiture/exon/blob/master/contrib/helix/TESTING.md)

This remains a preview. Completion uses the primary candidate at compatible
locations; independent per-cursor LSP edits and snippet groups are not guaranteed.
Builtin single-context snippets are tested; third-party editing plugins require
workflow validation. Full mouse/Helix-command parity, syntax-aware objects,
macro/dot-repeat parity and large-file performance remain outside this baseline.
Native Insert cursor movements can introduce native undo boundaries; selection
undo metadata is session-local and does not change Neovim's undo-file format.
