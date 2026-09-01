##
# Package: renoise-redux
# Purpose: Renoise Redux 1.4.4 — sample/synth VST3 plugin (user's licensed
#   build, backstage.renoise.com download). Installed as a standard VST3
#   bundle under $out/lib/vst3; hosts find it via the ~/.vst3 symlink set up
#   in modules/user/nix-maid/apps/supercollider.nix (or any VST3 path).
{
  lib,
  stdenv,
  alsa-lib,
  libx11,
  libxext,
}:

stdenv.mkDerivation rec {
  pname = "renoise-redux";
  version = "1.4.4";

  src = ./../../files/sources/rns_rdx_144_linux_x86_64.tar.gz;

  buildInputs = [
    alsa-lib
    libx11
    libxext
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/vst3
    cp -r renoise_redux_x86_64/renoise_redux.vst3 $out/lib/vst3/
    runHook postInstall
  '';

  postFixup = ''
    # The .so links against X11/Xext/asound/stdc++ from the nix store; add
    # their dirs to the RUNPATH so hosts can dlopen the plugin. libstdc++
    # comes from the build cc (same pattern as the nixpkgs renoise package).
    plugin=$out/lib/vst3/renoise_redux.vst3/Contents/x86_64-linux/renoise_redux.so
    patchelf \
      --set-rpath ${lib.makeLibraryPath buildInputs}:${lib.getLib stdenv.cc.cc}/lib \
      $plugin
  '';

  meta = {
    description = "Renoise Redux — sample/synth VST3 plugin";
    homepage = "https://www.renoise.com/products/redux";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
