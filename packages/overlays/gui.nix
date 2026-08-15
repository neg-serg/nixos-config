inputs: final: prev:
let
  callPkg = final.neg.functions.callPkg; # shared helper (functions.nix)
in
{
  hyprland-qtutils = prev.hyprland-qtutils.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      for f in $(grep -RIl "Qt6::WaylandClientPrivate" . || true); do
        substituteInPlace "$f" --replace "Qt6::WaylandClientPrivate" "Qt6::WaylandClient"
      done
    '';
  });
  # Avoid pulling hyprland-qtutils into Hyprland runtime closure
  # Some downstream overlays add qtutils to PATH wrapping; disable that.
  hyprland = prev.hyprland.override { wrapRuntimeDeps = false; };
  andromeda-gtk-theme = callPkg (inputs.self + "/packages/andromeda-gtk-theme") { };
  flight-gtk-theme = callPkg (inputs.self + "/packages/flight-gtk-theme") { };
  matugen-themes = callPkg (inputs.self + "/packages/matugen-themes") { };
  wl = callPkg (inputs.self + "/packages/wl") { };
  wl-switcher = prev.callPackage (inputs.self + "/packages/wl-switcher") { };
  wallhaven = prev.callPackage (inputs.self + "/packages/wallhaven") { };
  hyprwhspr = prev.callPackage (inputs.self + "/packages/hyprwhspr") { };

  # hyprscratch: patched to exit after 5 event-listener failures
  # so systemd Restart=always can restart it with fresh Hyprland IPC env.
  hyprscratch =
    inputs.hyprscratch.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [ ./hyprscratch-keepalive-fix.patch ];
      });

  # vicinae: enable browser native host for tab search integration. The version
  # comes from nixpkgs (0.23.2). The earlier v0.23.1 pin + QML Tab/Shift+Tab
  # patch were dropped: the pin was never live before (shadowed by a second
  # override in overlay.nix) and downgraded the package — the running system
  # was on 0.23.2 without the patch. Re-port the Tab patch on top of the
  # nixpkgs version if the feature is wanted.
  vicinae = prev.vicinae.overrideAttrs (old: {
    # Tab/Shift+Tab navigate the item list (dmenu/rofi style) + Ctrl+C dismiss —
    # QML SearchBar patch, ported to v0.23.2 (packages/vicinae-tab-qml.patch).
    patches = (old.patches or [ ]) ++ [ ./../vicinae-tab-qml.patch ];
    cmakeFlags =
      builtins.filter (f: f != "-DINSTALL_BROWSER_NATIVE_HOST:STRING=OFF") (old.cmakeFlags or [ ])
      ++ [ "-DINSTALL_BROWSER_NATIVE_HOST:STRING=ON" ];
  });
}
