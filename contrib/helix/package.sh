#!/bin/sh
# Build/install only into the explicit output directory; leave user config alone.
set -eu
helix_build=${1:-build}
helix_prefix=${2:-build/helix-install}
helix_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
case "$helix_build" in /*) ;; *) helix_build="$helix_root/$helix_build" ;; esac
case "$helix_prefix" in /*) ;; *) helix_prefix="$helix_root/$helix_prefix" ;; esac

# The source shipped with a binary must describe the committed distribution.
git -C "$helix_root" diff --quiet HEAD -- || {
  printf '%s\n' 'Commit tracked changes before packaging the matching source.' >&2
  exit 1
}
cmake --install "$helix_build" --prefix "$helix_prefix" --strip
mkdir -p "$helix_prefix/share/neovim-helix"
cp "$helix_root/contrib/helix/init.lua" "$helix_root/contrib/helix/smoke.lua" \
  "$helix_root/contrib/helix/LICENSE-helix.vim" "$helix_root/LICENSE.txt" \
  "$helix_root/contrib/helix/DISTRIBUTION.md" "$helix_root/HELIX.md" \
  "$helix_prefix/share/neovim-helix/"

# Official bundles use the default bundled dependencies. Missing notices fail
# packaging rather than silently produce an incomplete distribution.
helix_licenses="$helix_prefix/share/neovim-helix/licenses"
mkdir -p "$helix_licenses"
for helix_notice in \
  libuv/LICENSE libuv/LICENSE-extra luajit/COPYRIGHT luv/LICENSE.txt \
  lpeg/lpeg.html lua_compat53/LICENSE utf8proc/LICENSE.md \
  unibilium/LICENSE unibilium/LGPLv3 unibilium/GPLv3 \
  treesitter/LICENSE treesitter/lib/src/unicode/LICENSE \
  treesitter_c/LICENSE treesitter_lua/LICENSE.md treesitter_vim/LICENSE \
  treesitter_vimdoc/LICENSE treesitter_query/LICENSE treesitter_markdown/LICENSE
do
  mkdir -p "$helix_licenses/$(dirname -- "$helix_notice")"
  cp "$helix_root/.deps/build/src/$helix_notice" "$helix_licenses/$helix_notice"
done
cp "$helix_root/src/mpack/LICENSE-MIT" "$helix_licenses/mpack-MIT"
cp "$helix_root/src/xdiff/COPYING" "$helix_licenses/xdiff-LGPL-2.1"
cp "$helix_root/src/xdiff/xhistogram.c" "$helix_licenses/xdiff-histogram.c"
cp "$helix_root/src/klib/kvec.h" "$helix_licenses/klib-kvec.h"

# Include application/build sources and the original dependency source archives.
# This also supplies source for statically linked LGPL libraries and permits
# rebuilding with modified libraries without a separate source request.
helix_source="$helix_prefix/share/neovim-helix/source.tar"
git -C "$helix_root" archive --format=tar HEAD > "$helix_source"
tar -rf "$helix_source" -C "$helix_root" .deps/build/downloads
gzip -f "$helix_source"
git -C "$helix_root" rev-parse HEAD > "$helix_prefix/share/neovim-helix/SOURCE_COMMIT"

"$helix_prefix/bin/nvim" --headless -i NONE -u NONE \
  -l "$helix_prefix/share/neovim-helix/smoke.lua" \
  "$helix_prefix/bin/nvim" "$helix_prefix/share/neovim-helix/init.lua"

helix_parent=$(dirname -- "$helix_prefix")
helix_name=$(basename -- "$helix_prefix")
tar -C "$helix_parent" -czf "$helix_prefix.tar.gz" "$helix_name"
cd -- "$helix_parent"
cmake -E sha256sum "$helix_name.tar.gz" > "$helix_name.tar.gz.sha256"
printf '%s\n' "$helix_prefix.tar.gz" "$helix_prefix.tar.gz.sha256"
