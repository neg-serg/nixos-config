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
  nyxt4-bin = let
    pname = "nyxt4-bin";
    version = "4.0.0-pre-release-13";
    src = prev.fetchurl {
      url = "https://github.com/atlas-engineer/nyxt/releases/download/${version}/Linux-Nyxt-x86_64.tar.gz";
      hash = "sha256-9kwgLVvnqXJnL/8jdY2jly/bS2XtgF9WBsDeoXNHX8M=";
    };
    appimage = prev.runCommand "extract-nyxt" {} ''
      mkdir -p $out
      tar xf ${src} -C $out
      mv $out/Nyxt-x86_64.AppImage $out/${pname}.AppImage
    '';
  in
    prev.appimageTools.wrapType2 {
      inherit pname version;
      src = "${appimage}/${pname}.AppImage";
      extraPkgs = pkgs:
        with pkgs; [
          enchant
          # Common deps for GUI apps / Electron / WebKit
          gsettings-desktop-schemas
          glib
          gtk3
          cairo
          pango
          gdk-pixbuf
          at-spi2-atk
          at-spi2-core
          dbus
          libdrm
          libxkbcommon
          mesa
          nspr
          nss
          cups
          alsa-lib
          # GStreamer
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-good
          gst_all_1.gst-plugins-ugly
        ];
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
