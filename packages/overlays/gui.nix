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
  nyarchAssistantPkg = inputs.nyarch-assistant.packages.${prev.system}.default;
in
{
  kitty = prev.kitty.overrideAttrs (old: {
    env.NIX_CFLAGS_COMPILE = toString (old.env.NIX_CFLAGS_COMPILE or "") + " -O3";
  });
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
  "nyarch-assistant" = nyarchAssistantPkg;
  "_nyarch-assistant" = nyarchAssistantPkg;
  flight-gtk-theme = callPkg (inputs.self + "/packages/flight-gtk-theme") { };
  matugen-themes = callPkg (inputs.self + "/packages/matugen-themes") { };
  floorp-bin = prev.floorp-bin.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      # Remove MOZ_LEGACY_PROFILES=1 to prevent creation of ~/Floorp directory
      # and ensure it respects ~/.floorp defined in profiles.ini
      sed -i '/MOZ_LEGACY_PROFILES/d' $out/bin/floorp
    '';
  });
  oldschool-pc-font-pack = callPkg (inputs.self + "/packages/oldschool-pc-font-pack") { };
  surfingkeys-pkg = prev.callPackage (inputs.self + "/packages/surfingkeys-conf") {
    customConfig = inputs.self + "/files/surfingkeys.js";
  };
  tws = inputs.tws.packages.${prev.system}.default;
}
