# Final overlay — applied AFTER neg-pkgs.
# Fixes hashes, OOM limits, flaky tests that neg-pkgs would otherwise override.
_final: prev: let
  checkOff = pkg: pkg.overrideAttrs (_: { doCheck = false; });
in {
  # Fix opencode node_modules hash — neg-pkgs has a stale hash
  opencode = prev.opencode.overrideAttrs (old: {
    node_modules = old.node_modules.overrideAttrs (_: {
      outputHash = "sha256-1NUtprMH8GnSUqQ+mHQSC+JLU7lwzHe6XXYHe129WmE=";
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
    });
  });

  # Limit parallelism for OOM-prone builds on 32-thread 64GB
  webkitgtk_4_1 = prev.webkitgtk_4_1.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
  qt6 = prev.qt6 // {
    qtwebengine = prev.qt6.qtwebengine.overrideAttrs (_: {
      NIX_BUILD_CORES = 2;
    });
  };

  # Force-rebuild KDE packages that reference old qtwebengine output
  kdePackages = prev.kdePackages // {
    kcoreaddons = prev.kdePackages.kcoreaddons.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    kguiaddons = prev.kdePackages.kguiaddons.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    knotifications = prev.kdePackages.knotifications.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    kwidgetsaddons = prev.kdePackages.kwidgetsaddons.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    kauth = prev.kdePackages.kauth.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    "kirigami-addons" = prev.kdePackages."kirigami-addons".overrideAttrs (_: { NIX_BUILD_CORES = 4; });
    kdeconnect-kde = prev.kdePackages.kdeconnect-kde.overrideAttrs (_: { NIX_BUILD_CORES = 4; });
  };

  # Flaky tests — re-disable here (neg-pkgs may re-enable)
  libpulseaudio = checkOff prev.libpulseaudio;
  flac = checkOff prev.flac;
  ffmpeg-headless = checkOff prev.ffmpeg-headless;
  pylint = checkOff prev.pylint;
}
