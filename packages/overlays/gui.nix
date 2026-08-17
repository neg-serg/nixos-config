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
  camillagui = callPkg (inputs.self + "/packages/camillagui") { }; # web GUI for CamillaDSP

  # hyprscratch: patched to exit after 5 event-listener failures
  # so systemd Restart=always can restart it with fresh Hyprland IPC env.
  hyprscratch =
    inputs.hyprscratch.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [ ./hyprscratch-keepalive-fix.patch ];
      });

  # vicinae — MANUALLY PINNED: version and behavior are controlled here, not by
  # nixpkgs. nixpkgs updates will NOT touch this package. To bump: update
  # version/src hash (+ apiDeps/extensionManagerDeps) and re-verify the Tab
  # patch applies (git clone --branch v<X> ... && patch -p1 --dry-run).
  vicinae =
    let
      src = prev.fetchFromGitHub {
        owner = "vicinaehq";
        repo = "vicinae";
        tag = "v0.23.2";
        hash = "sha256-/5fGvMWlLlyd5ibK7y1dqIK1MTpLABj3v1M0r/VArww=";
      };
    in
    prev.vicinae.overrideAttrs (old: {
      version = "0.23.2";
      inherit src;
      # Tab/Shift+Tab navigate the item list (launcher-menu style) + Ctrl+C
      # dismiss — QML SearchBar patch, ported to v0.23.2.
      patches = (old.patches or [ ]) ++ [ ./../vicinae-tab-qml.patch ];
      apiDeps = prev.fetchNpmDeps {
        src = "${src}/src/typescript/api";
        hash = "sha256-4FEaBDJK9abcgz+vptuL4wQ8zhp+wpLbbR4Y79BVhEg=";
      };
      extensionManagerDeps = prev.fetchNpmDeps {
        src = "${src}/src/typescript/extension-manager";
        hash = "sha256-pEgqFgvdz7Bcc+LznCI+KlD1XEfUuWFWjS24MJ7sx3k=";
      };
      cmakeFlags =
        builtins.filter (f: f != "-DINSTALL_BROWSER_NATIVE_HOST:STRING=OFF") (old.cmakeFlags or [ ])
        ++ [ "-DINSTALL_BROWSER_NATIVE_HOST:STRING=ON" ];
    });
}
