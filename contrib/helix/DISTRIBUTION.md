# Exon preview distribution

Exon is a modified Neovim distribution maintained at
<https://github.com/noahfraiture/exon>. For Helix bug reports or
source requests, contact the maintainer through
<https://github.com/noahfraiture/helix.vim/issues> (the original plugin's tracker).
It is not an official Neovim or Helix release.

The changes add an optional native selection-first mode, selection/edit APIs,
selection undo metadata, bundled Lua commands and configuration, integration
hooks and tests. The upstream base is Neovim v0.12.6. `HELIX.md` describes the
feature boundaries; this remains a preview, not a production-readiness claim.

## Licenses and redistribution

`LICENSE.txt` contains Neovim's Apache 2.0 and Vim licenses. The command policy
derived from `noahfraiture/helix.vim` retains its MIT notice in
`LICENSE-helix.vim`. Existing runtime notices also remain with their files.
These licenses permit open-source distribution and commercial use subject to
their conditions; this fork does not replace its dependencies' licenses.

`licenses/` contains notices from the bundled libraries and parsers: libuv,
LuaJIT (including Lua), Luv, LPeg, lua-compat-5.3, utf8proc, unibilium,
tree-sitter and its bundled grammars, mpack, klib and xdiff. LPeg's license
appears in its supplied `lpeg.html` manual. In particular, unibilium uses
LGPL 3 or later and xdiff includes LGPL 2.1 or later code. Retain the notices
and corresponding source when redistributing these bundles. There is no
additional restriction on modifying these library portions or reverse
engineering the combined work to debug library modifications.

## Matching source and rebuilding

Each binary bundle includes `share/neovim-helix/source.tar.gz` and
`SOURCE_COMMIT`. The source archive contains that exact committed application
source, runtime and build scripts, plus the original bundled dependency source
archives in `.deps/build/downloads`. Dependency URLs and SHA-256 hashes are in
`cmake.deps/deps.txt`; the build checks those hashes before extraction. The
sources include the dependencies' original copyright notices.

From the extracted binary bundle:

```sh
mkdir source
tar -xzf share/neovim-helix/source.tar.gz -C source
cd source
make CMAKE_BUILD_TYPE=RelWithDebInfo
VIMRUNTIME="$PWD/runtime" ./build/bin/nvim -u contrib/helix/init.lua
```

The macOS binary follows upstream's release settings: add
`CMAKE_EXTRA_FLAGS="-DENABLE_LIBINTL=OFF -DCMAKE_FIND_FRAMEWORK=NEVER"` to the
`make` command to match it. This avoids a Homebrew gettext dependency; the
macOS bundle consequently has no gettext UI translations. `DEPENDENCIES.txt`
records the binary/parser load dependencies, checked to use only system paths.

The prerequisites in `BUILD.md` apply. The default build uses the included
dependency downloads. To change a library, edit its extracted source under
`.deps/build/src`, rebuild it with its supplied build system into `.deps/usr`,
then rebuild Neovim. Build-tool downloads can still require network access.
This is source for rebuilding; it is not a claim of bit-for-bit reproducibility.
