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
  nyarchAssistantPkg = callPkg (inputs.self + "/packages/nyarch-assistant") { };
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
  # WinBoat: relax npm peer dependency resolution to avoid npm ci failures
  winboat = prev.winboat.overrideAttrs (old: {
    npmFlags = (old.npmFlags or [ ]) ++ [ "--legacy-peer-deps" ];
  });
  # Nyxt 4 pre-release binary (Electron/Blink backend). Upstream provides a single self-contained
  # ELF binary for Linux. Package it as a convenience while no QtWebEngine build is available.
  nyxt4-bin = prev.callPackage ../nyxt/default.nix { };
  "nyarch-assistant" = nyarchAssistantPkg;
  "_nyarch-assistant" = nyarchAssistantPkg;
  flight-gtk-theme = callPkg (inputs.self + "/packages/flight-gtk-theme") { };
  matugen-themes = callPkg (inputs.self + "/packages/matugen-themes") { };
  oldschool-pc-font-pack = callPkg (inputs.self + "/packages/oldschool-pc-font-pack") { };
  px437-ibm-conv-e = callPkg (inputs.self + "/packages/px437-ibm-conv-e") { };
  pyprland_fixed = prev.python3Packages.callPackage ../pyprland-fixed/default.nix { };
  surfingkeys-pkg = prev.callPackage (inputs.self + "/packages/surfingkeys-conf") {
    customConfig = inputs.self + "/files/surfingkeys.js";
  };
}
