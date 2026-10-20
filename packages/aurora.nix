# aurora — MPD client with its own Vulkan UI (winit + ash + cosmic-text, no
# GUI toolkit). Two binaries: aurora (the player) and aurora-probe (the
# start-up measurement the project grew out of).
#
# The source is ~/src/neg-player, which lives outside this flake. It arrives as
# the aurora-src git input, so the package builds the *committed* tree:
# installing what was committed is the point, and untracked files (target/)
# stay out of the store.
{
  lib,
  rustPlatform,
  makeWrapper,
  vulkan-loader,
  libGL,
  libxkbcommon,
  wayland,
  libx11,
  libxcursor,
  libxrandr,
  libxi,
  src,
}:

let
  # The renderer dlopens these by soname (src/preload.rs does it before winit
  # and ash ask, and it knows the NixOS store layout), but the wrapper is what
  # makes the package self-contained: a session without vulkan-loader in its
  # profile still gets a working window.
  runtimeLibs = [
    vulkan-loader
    libGL
    libxkbcommon
    wayland
    libx11
    libxcursor
    libxrandr
    libxi
  ];
in
rustPlatform.buildRustPackage {
  pname = "aurora";
  version = "0.1.0";

  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";

  # Only the player and its probe: the workspace also carries eleven plugin
  # crates, and they are dependencies of the player, not separate binaries.
  cargoBuildFlags = [
    "--locked"
    "-p"
    "aurora"
    "-p"
    "aurora-probe"
  ];

  # The test suite is a development contract, not a packaging step: it asserts
  # the layout against the user's own Iosevka build in ~/.local/share/fonts and
  # drives a scripted UI against a stub MPD daemon. Neither belongs in a
  # sandbox build, so the packaged binaries are what gets checked (the probe
  # runs without a window).
  doCheck = false;

  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    for prog in aurora aurora-probe; do
      wrapProgram "$out/bin/$prog" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
    done
  '';

  # Desktop entry, so a launcher, a file manager and MPRIS's DesktopEntry
  # property all resolve to this package.
  postInstall = ''
        install -Dm644 /dev/stdin $out/share/applications/aurora.desktop <<'DESKTOP'
    [Desktop Entry]
    Type=Application
    Name=aurora
    Comment=MPD client with a Vulkan UI
    Exec=aurora
    Terminal=false
    Categories=AudioVideo;Audio;Player;
    Keywords=mpd;music;player;audio;
    StartupWMClass=aurora
    DESKTOP
        install -Dm644 /dev/stdin $out/share/metainfo/aurora.metainfo.xml <<'META'
    <?xml version="1.0" encoding="UTF-8"?>
    <component type="desktop-application">
      <id>aurora</id>
      <name>aurora</name>
      <summary>MPD client with its own Vulkan UI</summary>
      <description>
        <p>A local MPD front end drawn with winit, ash and cosmic-text: one draw
        list per frame, a measured now-playing stack, plugins as workspace crates.</p>
      </description>
      <launchable type="desktop-id">aurora.desktop</launchable>
      <provides><binary>aurora</binary></provides>
    </component>
    META
  '';

  meta = lib.mkMeta {
    description = "MPD client with a Vulkan UI (winit + ash + cosmic-text)";
    license = lib.licenses.mit;
    mainProgram = "aurora";
  };
}
