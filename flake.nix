{
  description = "Exon: Neovim with an opt-in native Helix editing mode";

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
        (pkgs.neovim-unwrapped.override {
          treesitter-parsers = import ./contrib/helix/treesitter-parsers.nix {
            inherit (pkgs) lib fetchurl;
          };
        }).overrideAttrs
          (old: {
            pname = "exon";
            version = "0.13.0-helix-preview";
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
              for exon_command in exon ex nvim; do
                "$out/bin/$exon_command" --headless -i NONE -u NONE \
                  -l "$out/share/neovim-helix/smoke.lua" \
                  "$out/bin/$exon_command" "$out/share/neovim-helix/init.lua" nix
              done
            '';

            meta = old.meta // {
              description = "Exon: Neovim with native selection-first Helix editing";
              homepage = "https://github.com/noahfraiture/exon";
              changelog = "https://github.com/noahfraiture/exon/commits/master";
              mainProgram = "exon";
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
          exon = mkPackage pkgs;
          default = exon;
          neovim-helix = exon; # Compatibility for existing package references.
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          package = self.packages.${system}.default;
          wrapped = pkgs.wrapNeovimUnstable package {
            luaRcContent = ''
              vim.g.exon_wrapper_loaded = true
              vim.helix.setup()
            '';
          };
        in
        {
          native = package;
          commands = pkgs.runCommand "exon-command-checks" { } ''
            export XDG_CONFIG_HOME="$TMPDIR/config"
            export XDG_DATA_HOME="$TMPDIR/data"
            export XDG_STATE_HOME="$TMPDIR/state"
            export XDG_CACHE_HOME="$TMPDIR/cache"
            export NVIM_LOG_FILE="$TMPDIR/nvim.log"
            unset VIMINIT EXINIT VIMRUNTIME NVIM_APPNAME
            mkdir -p "$XDG_CONFIG_HOME/nvim"
            cat > "$XDG_CONFIG_HOME/nvim/init.lua" <<'EOF'
            vim.o.helix = true
            vim.g.exon_user_config_loaded = true
            EOF
            for exon_command in exon ex nvim; do
              echo "Testing $exon_command: user configuration and Nix wrapper configuration"
              ${package}/bin/$exon_command --headless -i NONE \
                '+lua if vim.fn.exists("+helix") ~= 1 or not vim.o.helix or not vim.g.exon_user_config_loaded then vim.cmd("cquit 1") end' '+qa!'
              ${wrapped}/bin/$exon_command --headless -i NONE \
                '+lua if vim.fn.exists("+helix") ~= 1 or not vim.o.helix or not vim.g.exon_wrapper_loaded then vim.cmd("cquit 1") end' '+qa!'
            done
            touch "$out"
          '';
        }
      );

      overlays.default =
        final: prev:
        let
          package = mkPackage prev;
        in
        {
          exon = package;
          neovim-helix = package;
        };
    };
}
