##
# Package: superdirt-mixer
# Purpose: SuperDirtMixer — SuperCollider quark providing a graphical mixing
#   UI for SuperDirt (gain, pan, reverb, EQ, compressor per orbit) with
#   preset management. Source: https://github.com/thgrund/SuperDirtMixer
{
  lib,
  stdenvNoCC,
  fetchgit,
}:
stdenvNoCC.mkDerivation {
  pname = "superdirt-mixer";
  version = "unstable-2026-07-07";

  src = fetchgit {
    url = "https://github.com/thgrund/SuperDirtMixer.git";
    rev = "9e645086ca01b36e94c97258a7dfd04dbbf13365";
    hash = "sha256-UJqrFQOVL1Z9BLCG3/KifFFhHjKdLcWTtW3u8nn8dRs=";
  };

  installPhase = ''
    runHook preInstall

    # SuperCollider looks for extensions in a fixed layout:
    #   $out/share/SuperCollider/extensions/<QuarkName>/
    extdir="$out/share/SuperCollider/extensions/SuperDirtMixer"
    mkdir -p "$extdir"

    # Copy class files (the actual SC code)
    cp -r classes "$extdir/"
    # Copy synth definitions (SynthDef files)
    cp -r synths "$extdir/"
    # Copy help source
    cp -r HelpSource "$extdir/"
    # Copy UI assets (SVG icons for the EQ curve)
    cp -r assets "$extdir/"
    # Copy default presets (JSON, user-writable copy lives in the home dir)
    cp -r presets "$extdir/"
    # Copy TidalCycles pattern functions (BootTidal.hs integration)
    cp -r tidal "$extdir/"
    # Copy the quark manifest
    cp SuperDirtMixer.quark "$extdir/"
    cp LICENSE README.md "$extdir/" 2>/dev/null || true

    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark with a graphical mixer UI for SuperDirt (TidalCycles audio engine)";
    longDescription = ''
      SuperDirtMixer is a mixer UI for the SuperDirt sound engine used with
      TidalCycles. It provides level indicators, gain, pan, reverb, EQ and
      compression settings for every orbit individually, plus preset
      management in JSON files. Depends on SuperDirt, EQui and JSONlib.
    '';
    homepage = "https://github.com/thgrund/SuperDirtMixer";
    license = licenses.gpl3; # LICENSE is GPL-3.0
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
