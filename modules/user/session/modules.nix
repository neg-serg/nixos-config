# Auto-import all .nix files in this directory (except modules.nix and default.nix)
let
  contents = builtins.readDir ./.;
  isImportable = name: type:
    type == "regular" && name != "modules.nix" && name != "default.nix" && builtins.match ".*\.nix" name != null;
  names = builtins.filter (n: isImportable n contents.${n}) (builtins.attrNames contents);
in {
  imports = map (n: ./. + "/${n}") names;
}
