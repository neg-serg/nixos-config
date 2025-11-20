inputs: final: prev: let
  callPkg = path: extraArgs: let
    f = import path;
    wantsInputs = builtins.hasAttr "inputs" (builtins.functionArgs f);
    autoArgs =
      if wantsInputs
      then {inherit inputs;}
      else {};
  in
    prev.callPackage path (autoArgs // extraArgs);
  packagesRoot = inputs.self + "/packages";
in {
  hyprland-qtutils = prev.hyprland-qtutils.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        for f in $(grep -RIl "Qt6::WaylandClientPrivate" . || true); do
          substituteInPlace "$f" --replace "Qt6::WaylandClientPrivate" "Qt6::WaylandClient"
        done
      '';
  });

  wf-recorder = prev.wf-recorder.overrideAttrs (old: {
    version = "0.6.0";
    src = prev.fetchFromGitHub {
      owner = "ammen99";
      repo = "wf-recorder";
      rev = "refs/tags/v0.6.0";
      hash = "sha256-CY0pci2LNeQiojyeES5323tN3cYfS3m4pECK85fpn5I=";
    };
    patches = [];
  });

  # Avoid pulling hyprland-qtutils into Hyprland runtime closure
  # Some downstream overlays add qtutils to PATH wrapping; disable that.
  hyprland = prev.hyprland.override {wrapRuntimeDeps = false;};

  # Nyxt 4 pre-release binary (Electron/Blink backend). Upstream provides a single self-contained
  # ELF binary for Linux. Package it as a convenience while no QtWebEngine build is available.
  nyxt4-bin = prev.stdenvNoCC.mkDerivation rec {
    pname = "nyxt4-bin";
    version = "4.0.0-pre-release-13";

    src = prev.fetchurl {
      url = "https://github.com/atlas-engineer/nyxt/releases/download/${version}/Linux-Nyxt-x86_64.tar.gz";
      # Note: despite the name, this is a single ELF binary (static-pie).
      hash = "sha256-9kwgLVvnqXJnL/8jdY2jly/bS2XtgF9WBsDeoXNHX8M=";
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      if gzip -t "$src" >/dev/null 2>&1; then
        # Some releases ship a gzipped single binary under a misleading name.
        gzip -dc "$src" > "$out/bin/nyxt"
        chmod 0755 "$out/bin/nyxt"
      else
        install -Dm0755 "$src" "$out/bin/nyxt"
      fi
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Nyxt 4 pre-release (Electron/Blink) binary";
      homepage = "https://nyxt.atlas.engineer";
      license = licenses.bsd3;
      platforms = ["x86_64-linux"];
      mainProgram = "nyxt";
      maintainers = with maintainers; [];
    };
  };

  flight-gtk-theme = callPkg (inputs.self + "/packages/flight-gtk-theme") {};
}
