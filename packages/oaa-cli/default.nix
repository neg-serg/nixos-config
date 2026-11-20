{
  lib,
  stdenv,
  fetchurl,
}:

# The `oaa` command-line front end to the same C engine the application runs:
# a text/JSON/CSV report for an audio file, and with `--target` an exit code
# (0 all clear, 2 out of delivery spec, 1 unreadable) a release pipeline can
# fail on. Upstream ships it as a prebuilt bundle with no Flutter runtime, so
# there is nothing to patch — the ELF needs only glibc and libstdc++.
stdenv.mkDerivation (finalAttrs: {
  pname = "oaa-cli";
  version = "0.16.0";

  src = fetchurl {
    name = "oaa-cli-${finalAttrs.version}-Linux.tar.gz";
    url = "https://github.com/JonasGrunau/open_audio_analyzer/releases/download/v${finalAttrs.version}/oaa-cli-Linux.tar.gz";
    hash = "sha256-BRpIGfxaUuDEQU7e95nOvOZ8/NN3x2PUaUKLRzLsgXc=";
  };

  # The archive is `bin/` and `lib/` at the root, with no directory to name.
  sourceRoot = ".";

  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;

  # `bin/oaa` is dartaotruntime with the Dart AOT snapshot carried inside it;
  # `strip` throws that away and the binary then reads its first argument as a
  # snapshot path ("…: not an AOT snapshot, it cannot be run"). Measured, not
  # assumed: the stripped build failed exactly that way.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    # The engine is opened by a path the Dart side builds relative to its own
    # executable — `../lib/liboaa_engine.so` — not by soname, so lib/ has to
    # stay a sibling of bin/: LD_LIBRARY_PATH cannot rescue a wrong layout.
    # A symlink in bin/ is enough; the kernel resolves it and /proc/self/exe
    # still names the real file inside libexec.
    install -Dm755 bin/oaa $out/libexec/oaa/bin/oaa
    install -Dm644 lib/liboaa_engine.so $out/libexec/oaa/lib/liboaa_engine.so
    mkdir -p $out/bin
    ln -s $out/libexec/oaa/bin/oaa $out/bin/oaa

    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "Offline loudness/dynamics analysis for audio files, with a delivery-target verdict as exit code";
    homepage = "https://open-audio-analyzer.com/docs";
    license = lib.licenses.gpl3Plus;
    mainProgram = "oaa";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
