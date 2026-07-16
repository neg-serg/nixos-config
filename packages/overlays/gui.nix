inputs: _: prev:
let
  callPkg =
    path: extraArgs:
    let
      f = import path;
      wantsInputs = builtins.hasAttr "inputs" (builtins.functionArgs f);
      autoArgs = if wantsInputs then { inherit inputs; } else { };
    in
    prev.callPackage path (autoArgs // extraArgs);
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
  oldschool-pc-font-pack = callPkg (inputs.self + "/packages/oldschool-pc-font-pack") { };
  surfingkeys-pkg = prev.callPackage (inputs.self + "/packages/surfingkeys-conf") {
    customConfig = inputs.self + "/files/surfingkeys.js";
  };
  wl = callPkg (inputs.self + "/packages/wl") { };
  rofiw = callPkg (inputs.self + "/packages/rofiw") { };

  skwd = prev.callPackage (inputs.self + "/packages/skwd") {
    skwd-src = inputs.skwd;
    skwd-daemon = inputs.skwd-daemon.packages.${prev.stdenv.hostPlatform.system}.default;
  };

  exo = prev.callPackage (inputs.self + "/packages/exo") {
    exo-src = inputs.exo;
  };

  # hyprscratch: patched to exit after 5 event-listener failures
  # so systemd Restart=always can restart it with fresh Hyprland IPC env.
  hyprscratch =
    inputs.hyprscratch.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [ ./hyprscratch-keepalive-fix.patch ];
      });

  optiscaler = prev.callPackage (inputs.self + "/packages/optiscaler") { };

  # Bump vicinae to latest stable (v0.23.1) — locked nixpkgs has v0.22.3
  vicinae =
    let
      src = prev.fetchFromGitHub {
        owner = "vicinaehq";
        repo = "vicinae";
        tag = "v0.23.1";
        hash = "sha256-qFDb6I9w9F/KfRVHmwezykv7y/Tb8BjJQD2v5AxlEfU=";
      };
    in
    prev.vicinae.overrideAttrs (old: {
      version = "0.23.1";
      inherit src;
      patches = prev.lib.unique ((old.patches or [ ]) ++ [
        # Tab/Shift+Tab navigate item list (dmenu/rofi style) — handled in QML
        # because Qt's QML focus navigation intercepts bare Tab before C++
        ./../vicinae-tab-qml.patch
      ]);
      apiDeps = prev.fetchNpmDeps {
        src = "${src}/src/typescript/api";
        hash = "sha256-Im8fSG9sbaSynrN5gLsWVaPgH5g4Zp+x+FUPIBXrKjg=";
      };
      extensionManagerDeps = prev.fetchNpmDeps {
        src = "${src}/src/typescript/extension-manager";
        hash = "sha256-pEgqFgvdz7Bcc+LznCI+KlD1XEfUuWFWjS24MJ7sx3k=";
      };
    });
}
