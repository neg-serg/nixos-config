{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  gtk3,
  libepoxy,
  libpulseaudio,
  alsa-lib,
  libusb1,
  freetype,
  fontconfig,
}:

# Upstream ships prebuilt Linux artefacts only (AppImage, flatpak, tar.gz); this
# packages the tar.gz. The GTK stack the Flutter runner NEEDs, plus libepoxy and
# the plugin's freetype/fontconfig, are patched in by autoPatchelfHook.
#
# Everything else the audio path needs is dlopen'd at runtime — sonames grepped
# out of the bundle: libpulse.so.0 and libasound.so.2 (the engine's miniaudio
# picks one of those) and libusb-1.0.so.0 (liboaa_usb, the USB route to a tablet
# display) — and dlopen is the one path an ELF patcher cannot rewrite, so those
# three ride the LD_LIBRARY_PATH wrapper. libjack.so.0 is deliberately NOT
# supplied: the host's pipewire-jack already owns the graph, and a second
# libjack ahead of it on the search path would hand the app a jackd nobody runs.
stdenv.mkDerivation (finalAttrs: {
  pname = "open-audio-analyzer";
  version = "0.16.0";

  src = fetchurl {
    name = "Open.Audio.Analyzer-${finalAttrs.version}-linux-x86_64.tar.gz";
    url = "https://github.com/JonasGrunau/open_audio_analyzer/releases/download/v${finalAttrs.version}/Open.Audio.Analyzer-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-umtF2+ORVgdCiBZd/JCzYec1c76uGZYmcnPiXEy4by0=";
  };

  sourceRoot = "Open Audio Analyzer-${finalAttrs.version}-linux-x86_64";

  # Whatever miniaudio opens by name rather than over a device node.
  runtimeLibs = [
    libpulseaudio
    alsa-lib
    libusb1
  ];

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    gtk3
    libepoxy
    (lib.getLib stdenv.cc.cc)
    freetype
    fontconfig
  ];

  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;

  # libapp.so is the Dart AOT snapshot; `strip` rewrites sections inside it and
  # a stripped snapshot is a crash on launch, not a smaller binary.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    # Flutter resolves its asset directory and the bundled engine through
    # /proc/self/exe, so the bundle (`data/`, `lib/`) has to stay next to the
    # real ELF. bin/ therefore carries a wrapper, not the binary.
    mkdir -p $out/libexec/open-audio-analyzer
    cp -a app/. $out/libexec/open-audio-analyzer/

    mkdir -p $out/bin
    makeWrapper $out/libexec/open-audio-analyzer/open-audio-analyzer $out/bin/open-audio-analyzer \
      --prefix LD_LIBRARY_PATH : "$out/libexec/open-audio-analyzer/lib:${lib.makeLibraryPath finalAttrs.runtimeLibs}" \
      --prefix XDG_DATA_DIRS : "${gtk3}/share"

    # Upstream desktop entry, icon theme set and AppStream metadata; Exec and
    # Icon name the wrapper and the hicolor icon, so the menu entry is complete.
    cp -a share/. $out/share/

    # The VST3 measures what a DAW plays and streams it to the app over
    # 127.0.0.1, so it is only useful beside it. A Nix package cannot write
    # ~/.vst3, which is the directory a DAW scans: symlink the bundle there.
    mkdir -p $out/lib/vst3
    cp -a vst3/. $out/lib/vst3/

    install -Dm644 LICENSE.txt -t $out/share/doc/open-audio-analyzer/
    install -Dm644 README.txt -t $out/share/doc/open-audio-analyzer/

    runHook postInstall
  '';

  # libGL is not in runtimeLibs on purpose: NixOS resolves it through
  # /run/opengl-driver, and a store libglvnd ahead of it on LD_LIBRARY_PATH
  # would select llvmpipe over the host's driver.
  meta = lib.mkMeta {
    description = "Loudness and spectrum analyzer with a modular meter canvas (Flutter + C engine, upstream binary bundle)";
    homepage = "https://open-audio-analyzer.com";
    license = lib.licenses.gpl3Plus;
    mainProgram = "open-audio-analyzer";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
