# aurora — MPD client with its own Vulkan UI (winit + ash + cosmic-text, no
# GUI toolkit). Two binaries: aurora (the player) and aurora-probe (the
# start-up measurement the project grew out of).
#
# The source is neg-serg/aurora (private; checkout ~/src/aurora), which lives
# outside this flake. It arrives as the aurora-src git input, so the package
# builds the *committed* tree: installing what was committed is the point, and
# untracked files (target/) stay out of the store.
{
  lib,
  rustPlatform,
  makeWrapper,
  pkg-config,
  freetype,
  zlib,
  vulkan-loader,
  libGL,
  libxkbcommon,
  wayland,
  libx11,
  libxcursor,
  libxrandr,
  libxi,
  # The statusbar plugin's whole-track spectrogram is one `ffmpeg -lavfi showspectrumpic` per
  # track, cached in `~/.cache/aurora/spectra`: the player never decodes audio (MPD does), and a
  # picture of the file's whole timeline is the one thing the daemon cannot answer. It arrives
  # through the wrapper's PATH rather than a `buildInputs` entry, because it is a program to run
  # and not a library to link — and the wrapper is what makes the feature work under a session
  # whose profile has no ffmpeg of its own.
  ffmpeg,
  src,
  toolsOnly ? false,
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
  player = rustPlatform.buildRustPackage {
    pname = "aurora";
    version = "0.1.0";

    inherit src;

    cargoLock.lockFile = "${src}/Cargo.lock";

    # One package, two binaries: `cargo build -p aurora` builds both `aurora` and
    # `aurora-probe` — they are two `[[bin]]` targets of the root package. The
    # workspace's eleven plugin crates are dependencies, not separate binaries.
    cargoBuildFlags = [
      "--locked"
      "-p"
      "aurora"
    ];

    # The test suite is a development contract, not a packaging step: it asserts
    # the layout against the user's own Iosevka build in ~/.local/share/fonts and
    # drives a scripted UI against a stub MPD daemon. Neither belongs in a
    # sandbox build, so the packaged binaries are what gets checked (the probe
    # runs without a window).
    doCheck = false;

    # FreeType is the text rasteriser (the glyphs are hinted the way Pango hints them), so the
    # build asks pkg-config for it; zlib is freetype-sys's own dependency.
    nativeBuildInputs = [
      makeWrapper
      pkg-config
    ];
    buildInputs = [
      freetype
      zlib
    ];

    postFixup = ''
      # The player: the runtime libraries it dlopens, and the ffmpeg the status bar's spectrogram
      # runs. The probe measures start-up and draws no bar, so it takes only the libraries.
      wrapProgram "$out/bin/aurora" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
        --prefix PATH : "${lib.makeBinPath [ ffmpeg ]}"
      wrapProgram "$out/bin/aurora-probe" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
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
      Icon=aurora
      Terminal=false
      Categories=AudioVideo;Audio;Player;
      Keywords=mpd;music;player;audio;
      StartupWMClass=aurora
      DESKTOP
          # The same four curtain ribbons the top bar and the window icon draw, as a scalable
          # asset: one mark, three renderers, no file that can drift out of date.
          install -Dm644 /dev/stdin $out/share/icons/hicolor/scalable/apps/aurora.svg <<'SVG'
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
        <style>
          .tile { fill: #14161b; }
          .ribbon { fill: url(#fade); }
          .crest { fill: #8aa2c0; }
        </style>
        <defs>
          <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/>
            <stop offset="1" stop-color="#ffffff" stop-opacity="0.10"/>
          </linearGradient>
        </defs>
        <rect class="tile" x="6" y="6" width="116" height="116" rx="28"/>
        <rect class="ribbon" x="34" y="58" width="15" height="36" rx="3"/>
        <rect class="ribbon" x="52" y="44" width="15" height="50" rx="3"/>
        <rect class="crest" x="70" y="26" width="15" height="68" rx="3"/>
        <rect class="ribbon" x="88" y="38" width="15" height="56" rx="3"/>
      </svg>
      SVG
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
  };

  # The catalogue tools: the same pinned source, a different crate and a different closure. Both
  # bins live in `aurora-camilla`: `headphones` files models and applies them over the daemon's
  # websocket, `headphones-web` serves the same catalogue on loopback; neither needs the player's
  # Vulkan stack, and building them apart is what keeps `nix why-depends` honest.
  tools = rustPlatform.buildRustPackage {
    pname = "aurora-tools";
    version = "0.1.0";

    inherit src;

    cargoLock.lockFile = "${src}/Cargo.lock";

    cargoBuildFlags = [
      "--locked"
      "-p"
      "aurora-camilla"
      "--bin"
      "headphones"
      "--bin"
      "headphones-web"
    ];

    doCheck = false;

    meta = lib.mkMeta {
      description = "aurora tools: the headphone catalogue CLI and its loopback web page";
      license = lib.licenses.mit;
      mainProgram = "headphones";
    };
  };
in
if toolsOnly then tools else player
