inputs: _: prev: let
  callPkg = path: extraArgs: let
    f = import path;
    wantsInputs = builtins.hasAttr "inputs" (builtins.functionArgs f);
    autoArgs =
      if wantsInputs
      then {inherit inputs;}
      else {};
  in
    prev.callPackage path (autoArgs // extraArgs);
  nyarchAssistantPkg = callPkg (inputs.self + "/packages/nyarch-assistant") {};
in {
  # proton-ge-bin: use upstream pkgs.proton-ge-bin (removed custom definition)
  # wf-recorder: upstream has 0.6.0 now (removed override)

  # yandex-browser-stable: moved inline to modules/web/browsers.nix due to overlay corruption

  hyprland-qtutils = prev.hyprland-qtutils.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        for f in $(grep -RIl "Qt6::WaylandClientPrivate" . || true); do
          substituteInPlace "$f" --replace "Qt6::WaylandClientPrivate" "Qt6::WaylandClient"
        done
      '';
  });

  # Avoid pulling hyprland-qtutils into Hyprland runtime closure
  # Some downstream overlays add qtutils to PATH wrapping; disable that.
  hyprland = prev.hyprland.override {wrapRuntimeDeps = false;};

  # WinBoat: relax npm peer dependency resolution to avoid npm ci failures
  winboat = prev.winboat.overrideAttrs (old: {
    npmFlags = (old.npmFlags or []) ++ ["--legacy-peer-deps"];
  });

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

    # dontUnpack = true; # It is a proper tarball containing an AppImage

    nativeBuildInputs = [prev.makeWrapper];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      # The tarball contains Nyxt-x86_64.AppImage
      install -Dm755 Nyxt-x86_64.AppImage "$out/bin/nyxt"
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Nyxt 4 pre-release (Electron/Blink) binary";
      homepage = "https://nyxt.atlas.engineer";
      license = licenses.bsd3;
      platforms = ["x86_64-linux"];
      mainProgram = "nyxt";
      maintainers = [];
    };
  };

  "nyarch-assistant" = nyarchAssistantPkg;
  "_nyarch-assistant" = nyarchAssistantPkg;

  flight-gtk-theme = callPkg (inputs.self + "/packages/flight-gtk-theme") {};

  matugen-themes = callPkg (inputs.self + "/packages/matugen-themes") {};

  oldschool-pc-font-pack = callPkg (inputs.self + "/packages/oldschool-pc-font-pack") {};
  px437-ibm-conv-e = callPkg (inputs.self + "/packages/px437-ibm-conv-e") {};

  pyprland_fixed = prev.python3Packages.buildPythonApplication {
    pname = "pyprland";
    version = "2.5.0";
    src = prev.fetchFromGitHub {
      owner = "hyprland-community";
      repo = "pyprland";
      rev = "e82637d73207abd634a96ea21fa937455374d131";
      sha256 = "0znrp6x143dmh40nihlkzyhpqzl56jk7acvyjkgyi6bchzp4a7kn";
    };
    format = "pyproject";
    nativeBuildInputs = [prev.python3Packages.poetry-core];
    propagatedBuildInputs = with prev.python3Packages; [aiofiles asyncio-dgram];
    meta.mainProgram = "pypr";
  };
}
