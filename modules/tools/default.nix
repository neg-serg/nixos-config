{ neg, lib, ... }:
let
  inherit (builtins) concatStringsSep length;
  inherit (lib.lists) zipListsWith;
  inherit (lib.strings) escapeShellArg;
in
{
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };

  # create an overlay for nix-output-monitor to match the inconsistent
  # and frankly ugly icons with nerdfonts ones. they look a little larger
  # than before, but overall consistency is better in general.
  nixpkgs.overlays = [
    (
      final: prev:
      let
        oldIcons = [
          "↑"
          "↓"
          "⏱"
          "⏵"
          "✔"
          "⏸"
          "⚠"
          "∅"
          "∑"
        ];
        newIcons = [
          "f062" # 
          "f063" # 
          "f017" # 
          "f04b" # 
          "f00c" # 
          "f04c" # 
          "f071" # 
          "f1da" # 
          "f04a0" # 󰒠
        ];
      in
      {
        nix-output-monitor =
          assert length oldIcons == length newIcons;
          prev.nix-output-monitor.overrideAttrs (o: {
            postPatch = (o.postPatch or "") + ''
              sed -i ${
                escapeShellArg (concatStringsSep "\n" (zipListsWith (a: b: "s/${a}/\\\\x${b}/") oldIcons newIcons))
              } lib/NOM/Print.hs

              sed -i 's/┌/╭/' lib/NOM/Print/Tree.hs

              # Unknown activity types/results (activity 10113 from Determinate
              # Nix 3.23, result 10111) need no local patch any more: nixpkgs
              # backports maralorn/nix-output-monitor#321 itself on the
              # 2026-10-27 pin, turning unknown values into OtherType/
              # OtherResult instead of aborting the run. The former
              # nom-activity-types.patch applied the same changes and now
              # conflicts with that patch (reversed-patch detection), so it is
              # not applied here.
            '';
          });

        # nh puts nom on the wrapped binary's PATH; without this it keeps the
        # unpatched 2.2.0 and the fix would only apply to a bare `nom`.
        nh = prev.nh.override { nix-output-monitor = final.nix-output-monitor; };
      }
    )
    (
      final: prev:
      if prev ? fastfetch-unwrapped then
        {
          fastfetch-unwrapped = prev.fastfetch-unwrapped.overrideAttrs (old: {
            # Enable experimental Lua scripting in fastfetch format strings (2.64.0+).
            # lua5_4 explicitly: the unversioned `lua` alias does not exist with
            # allowAliases=false (flake/lib.nix).
            buildInputs = (old.buildInputs or [ ]) ++ [ final.lua5_4 ];
            cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DENABLE_LUA=ON" ];
          });
        }
      else
        { }
    )
  ];
}
