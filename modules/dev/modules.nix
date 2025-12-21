# Auto-import all subdirectories (with default.nix) and .nix files (except modules.nix, default.nix)
let
  contents = builtins.readDir ./.;
  isImportable = name: type:
    if type == "directory"
    then builtins.pathExists (./. + "/${name}/default.nix")
    else type == "regular" && name != "modules.nix" && name != "default.nix" && builtins.match ".*\.data\.nix" name == null && builtins.match ".*\.nix" name != null;
  names = builtins.filter (n: isImportable n contents.${n}) (builtins.attrNames contents);
in {
  imports = map (n: ./. + "/${n}") names;
}
