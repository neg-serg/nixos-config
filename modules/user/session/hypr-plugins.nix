{
  pkgs,
  lib,
  ...
}: let
  hy3Pkg = pkgs.hyprlandPlugins.hy3;
  hyprsplitPkg = pkgs.hyprlandPlugins.hyprsplit;
  mkPluginEntry = name: pkg:
    let
      # Copy plugin into its own store path so /etc/static/hypr/<name> refers to a
      # real file and Hyprland is not forced to follow nested symlinks.
      pluginFile = pkgs.runCommandLocal name {} ''
        install -Dm0644 ${pkg}/lib/${name} "$out"
      '';
    in {
      "static/hypr/${name}".source = pluginFile;
      "hypr/${name}".source = pluginFile;
    };
in {
  # Provide stable, GC-resistant paths for Hyprland plugins so users can reference
  # /etc/static/hypr/lib*.so (or /etc/hypr/lib*.so) without worrying about store hashes or
  # garbage collection.
  environment.etc = lib.mkMerge [
    (mkPluginEntry "libhy3.so" hy3Pkg)
    (mkPluginEntry "libhyprsplit.so" hyprsplitPkg)
  ];
}
