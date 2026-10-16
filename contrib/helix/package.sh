#!/bin/sh
# Build/install only into the explicit output directory; leave user config alone.
set -eu
helix_build=${1:-build}
helix_prefix=${2:-build/helix-install}
helix_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
case "$helix_build" in /*) ;; *) helix_build="$helix_root/$helix_build" ;; esac
case "$helix_prefix" in /*) ;; *) helix_prefix="$helix_root/$helix_prefix" ;; esac

cmake --install "$helix_build" --prefix "$helix_prefix" --strip
mkdir -p "$helix_prefix/share/neovim-helix"
cp "$helix_root/contrib/helix/init.lua" "$helix_root/contrib/helix/smoke.lua" \
  "$helix_root/contrib/helix/LICENSE-helix.vim" "$helix_root/HELIX.md" \
  "$helix_prefix/share/neovim-helix/"
"$helix_prefix/bin/nvim" --headless -i NONE -u NONE \
  -l "$helix_prefix/share/neovim-helix/smoke.lua" \
  "$helix_prefix/bin/nvim" "$helix_prefix/share/neovim-helix/init.lua"

helix_parent=$(dirname -- "$helix_prefix")
helix_name=$(basename -- "$helix_prefix")
tar -C "$helix_parent" -czf "$helix_prefix.tar.gz" "$helix_name"
cd -- "$helix_parent"
cmake -E sha256sum "$helix_name.tar.gz" > "$helix_name.tar.gz.sha256"
printf '%s\n' "$helix_prefix.tar.gz" "$helix_prefix.tar.gz.sha256"
