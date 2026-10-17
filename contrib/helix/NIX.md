# Install with Nix

Exon's default `master` branch contains a flake. It builds the fork using the
locked Nixpkgs Neovim recipe, including its Lua dependencies, parser grammars
and Neovim wrappers. The executable is named `nvim` and includes its matching
runtime. Nix does not enable the mode or modify your editor configuration.

## Try and build

Enable Nix's `nix-command` and `flakes` experimental features if needed:

```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

```sh
# Run with an empty configuration and native Helix mode enabled.
nix run github:noahfraiture/exon -- -u NONE --cmd 'set helix'

# Build without installing globally.
nix build github:noahfraiture/exon
./result/bin/nvim --version

# Install into your user profile, if you do not use a system/home module.
nix profile install github:noahfraiture/exon
```

## Add a flake input

```nix
inputs.exon.url = "github:noahfraiture/exon";
```

Where your `outputs` function has `inputs` in scope, use:

```nix
inputs.exon.packages.${pkgs.stdenv.hostPlatform.system}.default
```

For example, in an inline NixOS module inside your flake's outputs:

```nix
{ pkgs, ... }: {
  environment.systemPackages = [
    inputs.exon.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
```

In a separate module, pass `inputs` through `specialArgs` (or Home Manager's
`extraSpecialArgs`) before referring to it in the module arguments. Remove a
separate stock Neovim package from the same package list to avoid two `nvim`
executables competing in your profile.

Home Manager can wrap this package and configure Helix directly:

```nix
{ inputs, pkgs, ... }: {
  programs.neovim = {
    enable = true;
    package = inputs.exon.packages.${pkgs.stdenv.hostPlatform.system}.default;
    initLua = ''
      vim.helix.setup()
    '';
  };
}
```

Older Home Manager releases call `initLua` `extraLuaConfig`.

For NixOS's `programs.neovim`, use the same `package` attribute and enable the
mode in your normal `init.lua`. Standalone installation also uses your normal
configuration:

```lua
vim.helix.setup()
-- Or just: vim.o.helix = true
```

Remove the old plugin's `require('helix').setup()` if it is still configured.
Built-in/custom surrounds and keymaps are configured as in [HELIX.md](../../HELIX.md).

## Pinning, overlays and checks

Your `flake.lock` pins the fork revision. Update the `exon` input when
you want a newer build; ordinary rebuilds keep the locked version. The fork's
own `flake.lock` pins its tested Nixpkgs recipe and dependencies. Keeping that
input avoids coupling this build to the Neovim recipe in your system's Nixpkgs.
Using `inputs.nixpkgs.follows` deliberately replaces that tested dependency set.

The optional overlay adds `pkgs.exon` to a compatible Nixpkgs instance:

```nix
nixpkgs.overlays = [ inputs.exon.overlays.default ];
```

Package outputs cover `x86_64-linux`, `aarch64-linux` and `aarch64-darwin`.
The locked Nixpkgs no longer supports Intel macOS (`x86_64-darwin`).
Build checks run Nixpkgs' parser tests, the native Helix functional suite and
an installed executable/runtime/configuration smoke test:

```sh
nix flake check github:noahfraiture/exon --print-build-logs
```

This is a source build; the first build can take a while. Nix can reuse cached
dependencies and keeps the package separate from your existing editor. The
editing limitations of the current preview still apply.

## Existing inputs

The `neovim-helix` package and overlay names remain aliases of `exon`.
When moving from `github:noahfraiture/neovim/helix`, update the URL to
`github:noahfraiture/exon`; your local input name (for example `helix-nvim`)
can stay the same. `vim.helix.setup()` and the `nvim` executable keep their names.
The old `helix` branch is retained as a compatibility snapshot; development
continues on `master`.
