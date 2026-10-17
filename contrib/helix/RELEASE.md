An opt-in native selection-first mode for Neovim 0.12.6. Enable it with:

```lua
vim.o.helix = true
```

This distribution update adds Neovim's main license, dependency notices and
matching application/dependency source to every binary bundle. Version and
intro output now identify the executable as a Helix preview. The installed
smoke check verifies the notices, source files and fork identifier as well as
editing. See `share/neovim-helix/DISTRIBUTION.md` for rebuilding and
redistribution details.

The macOS build also drops an unintended Homebrew gettext dependency, following
upstream's release settings. Packaged executable/parser load dependencies must
use only macOS system paths. This build has no gettext UI translations.

Optional `vim.helix.setup()` and custom surround pairs remain available.
No per-delimiter mappings are needed for built-in pairs.

The [architecture and feature review](https://github.com/noahfraiture/exon/blob/master/contrib/helix/REVIEW.md)
records remaining gaps. This release remains based on 0.12.6; the planned
integration with 0.13 is not included. Native Insert commands outside the
vectorized set keep only the primary cursor, as completion already does.

Core owns the mode, selections, edit transactions and undo metadata. Bundled Lua
implements commands, including `mim`, `ma/`, `x`, word motions and multicursor
editing. Ordinary Vim mode remains the default.

Download and extract the archive for your platform. Linux X64 was built on
Ubuntu 24.04; macOS ARM64 is for Apple Silicon. Keep `bin` and `share` together.
To try the included configuration without editing your own:

```sh
./neovim-helix-Linux-X64/bin/nvim -i NONE \
  -u ./neovim-helix-Linux-X64/share/neovim-helix/init.lua
```

For macOS, substitute `neovim-helix-macOS-ARM64` for the directory name.
Remove the old `require('helix').setup()` when moving your own configuration to
the fork. `vim.pack` can still install ordinary plugins; the native mode requires
this executable and matching runtime.

[Instructions and manual test](https://github.com/noahfraiture/exon/blob/master/HELIX.md)
· [Verification record](https://github.com/noahfraiture/exon/blob/master/contrib/helix/TESTING.md)

The release archives are the exact artifacts from the workflow linked below.
Both platforms passed editor/API, built-in snippet/completion and installed-package
checks. The native tests also passed under address and undefined-behavior
sanitizers with leak detection enabled. SHA-256 files are attached.

This is a tested preview, not complete Helix parity. Completion keeps only the
primary cursor; built-in snippet placeholders use Vim Select mode. External
completion/snippet plugins need integration testing. Macro/dot-repeat parity,
syntax-aware textobjects, full mouse behavior, advanced multicursor indentation
and very-large-file performance remain unfinished.
