{
  pkgs,
  lib,
  ...
}: let
  hy3Pkg = pkgs.hyprlandPlugins.hy3;
  hyprsplitPkg = pkgs.hyprlandPlugins.hyprsplit;
  hyprVrrPkg = lib.attrByPath ["hyprlandPlugins" "hyprland-vrr"] null pkgs;
in {
  # Provide stable, GC-resistant paths for Hyprland plugins so users can reference
  # /etc/hypr/lib*.so without worrying about store hashes or garbage collection.
  environment.etc = lib.mkMerge (
    [
      {"hypr/libhy3.so".source = "${hy3Pkg}/lib/libhy3.so";}
      {"hypr/libhyprsplit.so".source = "${hyprsplitPkg}/lib/libhyprsplit.so";}
    ]
    ++ lib.optional (hyprVrrPkg != null) {
      "hypr/libhyprland-vrr.so".source = "${hyprVrrPkg}/lib/libhyprland-vrr.so";
    }
  );
}
