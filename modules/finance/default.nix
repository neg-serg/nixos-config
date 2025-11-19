{lib, ...}: let
  here = ./.;
  entries = builtins.readDir here;
  imports = lib.filter (p: p != null) (
    lib.mapAttrsToList (
      name: type: let
        path = here + "/${name}";
      in
        if name == "default.nix" then null
        else if type == "regular" && lib.hasSuffix ".nix" name then path
        else if type == "directory" && builtins.pathExists (path + "/default.nix") then path
        else null
    )
    entries
  );
in {inherit imports;}
