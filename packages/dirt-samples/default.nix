##
# Package: dirt-samples
# Purpose: Dirt-Samples — the audio sample library for SuperDirt/TidalCycles.
#   Organized into named directories (bd, sn, hh, …) each containing wav files.
# Source: https://github.com/musikinformatik/Dirt-Samples
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "dirt-samples";
  version = "unstable-2025-07-21";

  src = fetchFromGitHub {
    owner = "musikinformatik";
    repo = "Dirt-Samples";
    rev = "1d67800f9676a012dd48081279713d8d95d73163";
    hash = "sha256-/w4qzraivPpYXl5UYnfc28k9M8B7zUU/9d4arng9G4c=";
  };

  installPhase = ''
    runHook preInstall

    # Place samples where SuperDirt expects them:
    #   $out/share/Dirt-Samples/
    # The Tidal startup script (~/.config/SuperCollider/superdirt_startup.scd)
    # points ~dirt.loadSoundFiles at this path explicitly.
    mkdir -p "$out/share/Dirt-Samples"

    # Copy all sample directories (each is a sound name like "bd", "sn", "hh")
    for dir in */; do
      # Skip non-sample files
      case "$dir" in
        Dirt-Samples.quark|README.md|.git*)
          continue
          ;;
      esac
      cp -r "$dir" "$out/share/Dirt-Samples/"
    done

    # Also copy the quark manifest so SC quark system can discover it
    cp Dirt-Samples.quark "$out/share/Dirt-Samples/" 2>/dev/null || true

    runHook postInstall
  '';

  meta = with lib; {
    description = "Audio sample library for SuperDirt / TidalCycles live coding";
    longDescription = ''
      The standard sample library used by SuperDirt, containing percussive
      and tonal samples organized by sound name (bd, sn, hh, bass, etc.).
      Required for SuperDirt to produce anything beyond raw oscillators.
    '';
    homepage = "https://github.com/musikinformatik/Dirt-Samples";
    license = licenses.cc0; # CC0/public-domain sample sets
    platforms = platforms.all;
    maintainers = [ ];
  };
}
