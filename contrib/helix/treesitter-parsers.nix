{ lib, fetchurl }:
let
  # Keep Nix parsers on the exact sources used by upstream's bundled build.
  dependencies = builtins.readFile ../../cmake.deps/deps.txt;
  value =
    name:
    let
      match = builtins.match (".*\n" + name + " ([^\n]+)\n.*") dependencies;
    in
    if match == null then throw "Missing Neovim dependency: ${name}" else builtins.head match;
in
lib.genAttrs
  [
    "c"
    "diff"
    "lua"
    "markdown"
    "query"
    "vim"
    "vimdoc"
  ]
  (
    language:
    let
      key = "TREESITTER_${lib.toUpper language}";
    in
    {
      src = fetchurl {
        url = value "${key}_URL";
        sha256 = value "${key}_SHA256";
      };
    }
  )
