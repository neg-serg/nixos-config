##
# Package: irori
# Irori — native game launcher for Epic Games, GOG, Amazon Games, ZOOM Platform,
# itch.io, Steam and emulated games (GPUI/Rust, one process, no browser).
#
# Upstream's supported Linux artifact is the release tarball with prebuilt
# binaries (docs/PLATFORMS.md: cross-building the GPUI/WebKit stack is not the
# supported workflow), so this is a repack, not a source build. The tarball is
# checked against the release's SHA256SUMS whenever the version is bumped.
#
# Layout: both binaries stay flat in libexec/irori/ because the app starts its
# sign-in helper from beside its own executable; bin/ holds symlinks only. The
# graphics backends (Vulkan, Wayland, EGL) are loaded with dlopen() instead of
# being linked, and dlopen() resolves through the RUNPATH of the object that
# called it — so the release binaries get those libraries as DT_NEEDED entries
# (installPhase) and autoPatchelfHook puts their directories into RUNPATH. The
# wrapper deliberately sets no LD_LIBRARY_PATH: Irori passes its environment to
# the games it launches, and a wrapper-wide library path would shadow the Steam
# runtime, Proton's and umu's own libraries inside every game.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  patchelf,
  wrapGAppsHook3,
  bubblewrap,
  cairo,
  gdk-pixbuf,
  glib,
  glib-networking,
  gsettings-desktop-schemas,
  gtk3,
  libglvnd,
  libsoup_3,
  libxcb,
  libxkbcommon,
  udev,
  vulkan-loader,
  wayland,
  webkitgtk_4_1,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "irori";
  version = "1.1.0";

  src = fetchurl {
    name = "Irori-${finalAttrs.version}-linux.tar.gz";
    url = "https://github.com/irori-app/irori/releases/download/v${finalAttrs.version}/Irori-${finalAttrs.version}-linux.tar.gz";
    hash = "sha256-sT4V8ZUA0j0/FpG7N373Uk+6YdEQaDKCp8GhPDi/JB0=";
  };

  sourceRoot = "Irori";

  nativeBuildInputs = [
    autoPatchelfHook
    patchelf
    wrapGAppsHook3
  ];

  # DT_NEEDED of the app: libudev (controller discovery), libxcb,
  # libxkbcommon, libxkbcommon-x11. The sign-in window (irori-sign-in) is a
  # GTK 3 + WebKitGTK 4.1 program, and libsoup 3 is what WebKit's HTTPS
  # sign-ins go through (glib-networking supplies its TLS backend).
  buildInputs = [
    (lib.getLib stdenv.cc.cc) # libgcc_s
    cairo
    gdk-pixbuf
    glib
    glib-networking # TLS backend libsoup uses for HTTPS logins
    gsettings-desktop-schemas # GSettings schemas WebKitGTK reads
    gtk3
    libglvnd # libEGL, dlopen()ed by the GPUI backend probe
    libsoup_3
    libxcb
    libxkbcommon
    udev
    vulkan-loader # libvulkan, the renderer
    wayland # libwayland-client/-egl, the Wayland backend
    webkitgtk_4_1
  ];

  dontConfigure = true;
  dontBuild = true;

  # wrapGAppsHook3 would wrap every executable in libexec on its own; both
  # binaries are wrapped once below instead, where the bwrap PATH addition lives.
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 irori $out/libexec/irori/irori
    install -Dm755 irori-sign-in $out/libexec/irori/irori-sign-in

    install -Dm644 irori.desktop $out/share/applications/irori.desktop
    install -Dm644 irori.svg $out/share/icons/hicolor/scalable/apps/irori.svg
    install -Dm644 app.irori.Irori.metainfo.xml \
      $out/share/metainfo/app.irori.Irori.metainfo.xml

    # The backends the app dlopen()s. Making them DT_NEEDED is what puts their
    # directories into the RUNPATH autoPatchelfHook writes (it derives RUNPATH
    # from DT_NEEDED), and dlopen() then finds them through the executable's
    # RUNPATH as well; see the header for why this is not LD_LIBRARY_PATH.
    for lib in libvulkan.so.1 libEGL.so.1 libwayland-client.so.0 libwayland-egl.so.1; do
      patchelf --add-needed "$lib" $out/libexec/irori/irori
    done

    runHook postInstall
  '';

  postFixup = ''
    for prog in irori irori-sign-in; do
      # Irori's per-game "bubblewrap sandbox" shells out to bwrap; without it
      # the app reports the sandbox as unavailable and launches games bare.
      wrapGApp $out/libexec/irori/$prog --suffix PATH : "${lib.makeBinPath [ bubblewrap ]}"
    done

    # Expose the wrapped binaries, keeping libexec/irori flat for the app's
    # sibling lookup of irori-sign-in. The targets are $out-absolute here;
    # nixpkgs' make-symlinks-relative fixup rewrites them inside the output.
    mkdir -p $out/bin
    ln -s "$out/libexec/irori/irori" "$out/bin/irori"
    ln -s "$out/libexec/irori/irori-sign-in" "$out/bin/irori-sign-in"
  '';

  meta = lib.mkMeta {
    description = "Game launcher for Epic Games, GOG, Amazon Games, ZOOM Platform, itch.io and Steam";
    homepage = "https://irori.app";
    license = lib.licenses.mit;
    mainProgram = "irori";
    platforms = [ "x86_64-linux" ];
  };
})
