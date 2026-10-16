# Install with Nix

The `helix` branch contains a flake. It builds this fork from source using the
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
nix run github:noahfraiture/neovim/helix -- -u NONE --cmd 'set helix'

# Build without installing globally.
nix build github:noahfraiture/neovim/helix
./result/bin/nvim --version

# Install into your user profile, if you do not use a system/home module.
nix profile install github:noahfraiture/neovim/helix
```

## Add a flake input

```nix
inputs.helix-nvim.url = "github:noahfraiture/neovim/helix";
```

Where your `outputs` function has `inputs` in scope, use:

```nix
inputs.helix-nvim.packages.${pkgs.stdenv.hostPlatform.system}.default
```

For example, in an inline NixOS module inside your flake's outputs:

```nix
{ pkgs, ... }: {
  environment.systemPackages = [
    inputs.helix-nvim.packages.${pkgs.stdenv.hostPlatform.system}.default
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
    package = inputs.helix-nvim.packages.${pkgs.stdenv.hostPlatform.system}.default;
    extraLuaConfig = ''
      vim.helix.setup()
    '';
  };
}
```

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

Your `flake.lock` pins the fork revision. Update the `helix-nvim` input when
you want a newer build; ordinary rebuilds keep the locked version. The fork's
own `flake.lock` pins its tested Nixpkgs recipe and dependencies. Keeping that
input avoids coupling this build to the Neovim recipe in your system's Nixpkgs.
Using `inputs.nixpkgs.follows` deliberately replaces that tested dependency set.

The optional overlay adds `pkgs.neovim-helix` to a compatible Nixpkgs instance:

```nix
nixpkgs.overlays = [ inputs.helix-nvim.overlays.default ];
```

Package outputs cover `x86_64-linux`, `aarch64-linux` and `aarch64-darwin`.
The locked Nixpkgs no longer supports Intel macOS (`x86_64-darwin`). Build checks run Nixpkgs' parser tests, the native Helix
functional suite and an installed executable/runtime/configuration smoke test:

```sh
nix flake check github:noahfraiture/neovim/helix --print-build-logs
```

This is a source build; the first build can take a while. Nix can reuse cached
dependencies and keeps the package separate from your existing editor. The
editing limitations of the current preview still apply.
