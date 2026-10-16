{
  description = "Neovim with an opt-in native Helix editing mode";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPackage =
        pkgs:
        pkgs.neovim-unwrapped.overrideAttrs (old: {
          pname = "neovim-helix";
          version = "0.12.6-helix-preview";
          src = self;

          # Retain Nixpkgs' dependencies, parsers, remote-plugin patch and checks.
          postCheck = (old.postCheck or "") + ''
            TEST_FILE=test/functional/editor/helix_spec.lua cmake --build . --target functionaltest
          '';

          postInstall = (old.postInstall or "") + ''
            mkdir -p "$out/share/neovim-helix"
            cp ${self}/LICENSE.txt ${self}/contrib/helix/LICENSE-helix.vim \
              ${self}/contrib/helix/init.lua ${self}/contrib/helix/smoke.lua \
              "$out/share/neovim-helix/"
          '';

          postInstallCheck = (old.postInstallCheck or "") + ''
            "$out/bin/nvim" --headless -i NONE -u NONE \
              -l "$out/share/neovim-helix/smoke.lua" \
              "$out/bin/nvim" "$out/share/neovim-helix/init.lua" nix
          '';

          meta = old.meta // {
            description = "Neovim with native selection-first Helix editing";
            homepage = "https://github.com/noahfraiture/neovim/tree/helix";
            changelog = "https://github.com/noahfraiture/neovim/commits/helix";
            license = old.meta.license ++ [ pkgs.lib.licenses.mit ];
          };
        });
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        rec {
          neovim-helix = mkPackage pkgs;
          default = neovim-helix;
        }
      );

      checks = forAllSystems (system: {
        native = self.packages.${system}.default;
      });

      overlays.default = final: prev: {
        neovim-helix = mkPackage prev;
      };
    };
}
