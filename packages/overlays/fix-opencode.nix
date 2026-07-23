# Final overlay — applied AFTER neg-pkgs.
# Fixes hashes, OOM limits, flaky tests that neg-pkgs would otherwise override.
_final: prev: let
  checkOff = pkg: pkg.overrideAttrs (_: { doCheck = false; });
  # ISOEnts.zip with proxy-compatible hash (cache path gx73r58vbsj... already exists)
  isoEnts = prev.fetchurl {
    url = "https://xml.coverpages.org/ISOEnts.zip";
    hash = "sha256-3OQ1mjmW7S/TOtXqoRqbz8JLWwaZLiQpUTKwbbGambI=";
  };
in {
  # Disable flaky gjs tests
  gjs = prev.gjs.overrideAttrs (_: { doCheck = false; });

  # Limit parallelism for OOM-prone builds
  webkitgtk_4_1 = prev.webkitgtk_4_1.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
  qt6 = prev.qt6 // {
    qtwebengine = prev.qt6.qtwebengine.overrideAttrs (_: { NIX_BUILD_CORES = 2; });
  };

  # Force-rebuild KDE packages
  kdePackages = prev.kdePackages // {
    kcoreaddons = prev.kdePackages.kcoreaddons.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    kguiaddons = prev.kdePackages.kguiaddons.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    knotifications = prev.kdePackages.knotifications.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    kwidgetsaddons = prev.kdePackages.kwidgetsaddons.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    kauth = prev.kdePackages.kauth.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    "kirigami-addons" = prev.kdePackages."kirigami-addons".overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    kdeconnect-kde = prev.kdePackages.kdeconnect-kde.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
  };

  # Fix docbook ISOEnts.zip: overrideAttrs can't fix duplicate srcs,
  # so we bypass the standard unpack with a single-unzip installPhase.
  docbook_sgml_dtd_41 = prev.docbook_sgml_dtd_41.overrideAttrs (_: {
    src = isoEnts;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/sgml
      cd $out/sgml
      ${prev.unzip}/bin/unzip ${isoEnts}
    '';
  });
  docbook_sgml_dtd_45 = prev.docbook_sgml_dtd_45.overrideAttrs (_: {
    src = isoEnts;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/sgml
      cd $out/sgml
      ${prev.unzip}/bin/unzip ${isoEnts}
    '';
  });

  # Flaky tests — re-disable here (neg-pkgs may re-enable)
  libpulseaudio = checkOff prev.libpulseaudio;
  flac = checkOff prev.flac;
  ffmpeg-headless = checkOff prev.ffmpeg-headless;
  pylint = checkOff prev.pylint;
}
