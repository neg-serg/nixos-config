inputs: final: prev:
let
  callPkg = final.neg.functions.callPkg; # shared helper (functions.nix)
  pkg = final.neg.functions.pkg; # name → packages/<name>, no `../` counting
  # Shared builder for the install-as-is Vicinae extensions.
  mkVicinaeExtension = final.neg.functions.mkVicinaeExtension;
in
{
  # nixpkgs' hyprland wraps hyprland-qtutils into its runtime PATH
  # (wrapRuntimeDeps); the config runs hyprland-guiutils instead, so keep
  # qtutils out of the closure.
  hyprland = prev.hyprland.override { wrapRuntimeDeps = false; };
  # nixpkgs records propagatedBuildInputs as their *dev* outputs (make-derivation
  # maps them through getDev), so an icon theme's fallback propagation dragged
  # build-time dev trees into every runtime closure that wants it:
  # kora-icon-theme -> breeze-icons-dev -> qtsvg-dev -> qtbase-dev ->
  # vulkan-headers, plus gtk3-dev/icu4c-dev/hicolor-dev — 78 exclusive paths and
  # 133 MiB that nothing else needs. Kora only wants the fallback themes
  # themselves (its index.theme inherits "breeze,hicolor"), so propagate their
  # out outputs instead: getDev of a store-path string is that string.
  kora-icon-theme = prev.kora-icon-theme.overrideAttrs (_: {
    propagatedBuildInputs = [
      "${prev.adwaita-icon-theme}"
      "${prev.kdePackages.breeze-icons}"
      "${prev.hicolor-icon-theme}"
    ];
  });
  # hyprland-guiutils — not in the pinned nixpkgs yet, pinned locally (see
  # packages/hyprland-guiutils). It supersedes hyprland-qtutils and ships the
  # same five binaries (hyprland-dialog, -donate-screen, -update-screen,
  # -welcome, -run), so installing both would collide in the system profile.
  hyprland-guiutils = callPkg (pkg "hyprland-guiutils") { };
  # Waylandar is a standalone Quickshell calendar/dashboard; exposed as a flake
  # package so the system only carries an on-demand launcher.
  waylandar = callPkg (pkg "waylandar") { };
  # Patched Vivaldi build (wayland flags, bundled libffmpeg RUNPATH); the system
  # only carries a launcher.
  vivaldi-fixed = callPkg (pkg "vivaldi") { };
  # hypr-kdeconnect-fix — RemoteDesktop portal backend bridging KDE Connect /
  # Deskflow input to the wlroots virtual-input protocols Hyprland exposes.
  hypr-kdeconnect-fix = callPkg (pkg "hypr-kdeconnect-fix") { };
  # hyprqt6engine — not in the pinned nixpkgs yet, pinned locally (see
  # packages/hyprqt6engine). Qt6 platform theme + widget style for Hyprland;
  # the session selects it via QT_QPA_PLATFORMTHEME=hyprqt6engine and feeds it
  # ~/.config/hypr/hyprqt6engine.conf (modules/user/nix-maid/gui/qt.nix).
  hyprqt6engine = callPkg (pkg "hyprqt6engine") { };
  andromeda-gtk-theme = callPkg (pkg "andromeda-gtk-theme") { };
  flight-gtk-theme = callPkg (pkg "flight-gtk-theme") { };
  matugen-themes = callPkg (pkg "matugen-themes") { };
  wl = callPkg (pkg "wl") { };
  wl-switcher = callPkg (pkg "wl-switcher") { inherit mkVicinaeExtension; };
  wallhaven = callPkg (pkg "wallhaven") { inherit mkVicinaeExtension; };
  hyprwhspr = callPkg (pkg "hyprwhspr") { inherit mkVicinaeExtension; };
  aura = callPkg (pkg "aura") { inherit mkVicinaeExtension; }; # the emotion/CBT diary: record a note from the launcher
  camillagui = callPkg (pkg "camillagui") { }; # web GUI for CamillaDSP
  atrium = callPkg (pkg "atrium") { }; # Wayland multiseat display manager
  wordcraft = callPkg (pkg "wordcraft") { }; # Word-style word processor (docx/odt/rtf) + converter CLI
  sonda = callPkg (pkg "sonda") { }; # file manager for pleamar-wm that searches files by what they hold
  craft-anything = callPkg (pkg "craft-anything") { }; # reverse-engineering workbench + rebuild assistant (desktop app, CLI, MCP server)

  # ArtCraft suite: the six creative/office apps are on-demand roots
  # (modules/user/nix-maid/apps/craft-apps.nix) built on first launch, so the
  # system generation carries launchers and desktop entries only. Four of the
  # names shadow older nixpkgs recipes on purpose — the overlay builds the
  # newest upstream tags. `craft-fonts` is their shared build input (faces
  # embedded at build time), shadowing nixpkgs' older pin — see
  # packages/craft-fonts/default.nix.
  vectorcraft = callPkg (pkg "vectorcraft") { }; # vector illustration editor (SVG/PDF) + converter CLI
  figcraft = callPkg (pkg "figcraft") { }; # interface design and prototyping
  soundcraft = callPkg (pkg "soundcraft") { }; # digital audio workstation
  deckcraft = callPkg (pkg "deckcraft") { }; # presentations and slide shows
  gridcraft = callPkg (pkg "gridcraft") { }; # spreadsheet workbooks
  solidcraft = callPkg (pkg "solidcraft") { }; # parametric 3D CAD + headless CLI/MCP
  craft-fonts = callPkg (pkg "craft-fonts") { }; # shared ArtCraft font bundle (CRAFT_FONTS_DIR build input)

  # pleamar — Wayland desktop shell runtime (bars, launchers, notification
  # centres, docks, lock screens as animated scenes). Rev-pinned input in
  # flake.nix; nixpkgs follows the top-level pin so the Rust build reuses the
  # cached toolchain closure. The cursor is left exactly as upstream has it — no local patch touches
  # it, so a scene asks for the shape its zones declare, on entry and on leaving, like any other
  # client. And the right
  # click, which closed a scene that declares more than one surface no matter
  # what it does with the button (pleamar-right-click.patch). And the tray's menu: an item's
  # `com.canonical.dbusmenu` takes `parentId` as `i` in its first form and `u` in the spec's
  # newer one, items disagree, and the ask tried one of them — so half the tray answered
  # nothing (pleamar-dbusmenu.patch). And what the media service tells a scene: `playing` is a
  # bool, so a paused player and a stopped one look alike and a bar cannot keep its capsule through
  # a pause the way the reference shell does (pleamar-media-state.patch adds `paused` and
  # `can_go_next` beside `can_seek`), and the transport's other two buttons are gated on answers
  # the service did not carry (pleamar-transport-flags.patch adds `can_go_prev`, `can_play` and
  # `can_pause`, the reference's `MediaTransport.qml:71-76`). And where the song is: a song change is signalled with the new
  # `Metadata` while the player still answers the previous song's `Position`, and a scene
  # counting on from that reading sat four minutes off for the rest of the track
  # (pleamar-media-position.patch answers 0 for a track that changed under it). And the
  # software renderer: `ash`
  # resolves the DRM-modifier entry points when the device is made and *aborts* when the extension
  # is missing, so llvmpipe — and any ICD without `VK_EXT_image_drm_format_modifier` — died inside
  # `export_as` where the caller was ready to fall back to the system's swapchain
  # (pleamar-soft-render.patch refuses before the first call, with a line that says why). And the
  # lock: the render thread starts before the
  # platform has made the connection to ask with, its one request for `ext-session-lock` was
  # refused and remembered as sent, so a scene whose only surface is the lock never locked
  # anything and never painted (pleamar-lock-engage.patch makes the request repeatable and has
  # the platform wake the render once it can take it). And the box of a lock face: `size: full,
  # full` is compiled as a zero, and the engine centres that zero box on the monitor, which puts
  # the scene's origin at the monitor's CENTRE — every lock screen drawn from its own corner
  # (this one puts the clock at half the width and the card at 62 % of the height) lands half a
  # panel away, off the screen, with nothing said in the log. A `full` box now stands for the
  # face's own size, and the face prints its box and the corner it paints from
  # (pleamar-lock-full.patch). And Bluetooth: a failed `connect` reached only the engine's journal,
  # so a scene could not say why a device did not come up, and nothing could rename a paired device
  # or the adapter; the service now carries `error` and `adapter_name`, and the commands `rename`
  # and `adapter_name` (pleamar-bluetooth.patch).
  pleamar = inputs.pleamar.packages.${prev.stdenv.hostPlatform.system}.pleamar.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      # The one commit the pin used to carry in `neg-serg/pleamar`
      # (`fix/import-path-v0.4.29`): an `import` is resolved beside the path the
      # importing file was reached by, not beside its canonicalized checkout. It
      # applies cleanly on upstream main, and the scenes are loaded through a
      # symlink farm in ~/.config/pleamar, so without it the palette generated next
      # to the live tree is never read.
      ./pleamar-import-path.patch
      ./pleamar-right-click.patch
      ./pleamar-dbusmenu.patch
      ./pleamar-closed-surface.patch
      # Closed surfaces are taken out of the compositor instead of keeping an empty buffer
      # mapped: Hyprland composites —and, on the `pleamar` namespace, blurs— every mapped
      # layer on every damage, so the 19 full-monitor cards of a closed drawer scene are a
      # quarter of the GPU on an idle desktop (measured 2026-11-05: 26.4% of Hyprland's GPU
      # time against 0.8% with the scenes stopped). Hyprland clears its `configured` flag on
      # the unmap, so the surface also commits once more without a buffer: the compositor
      # arranges it and sends a new configure, which the toolkit acks, and only then may a
      # frame's buffer come back ("layerSurface was not configured, but a buffer was
      # attached" otherwise).
      ./pleamar-unmap-closed.patch
      ./pleamar-media-state.patch
      ./pleamar-transport-flags.patch
      ./pleamar-media-position.patch
      ./pleamar-soft-render.patch
      ./pleamar-lock-engage.patch
      ./pleamar-lock-full.patch
      ./pleamar-bluetooth.patch
    ];
  });

  # hyprscratch: patched to exit after 5 event-listener failures
  # so systemd Restart=always can restart it with fresh Hyprland IPC env.
  hyprscratch =
    inputs.hyprscratch.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [ ./hyprscratch-keepalive-fix.patch ];
      });

  # vicinae — MANUALLY PINNED: version and behavior are controlled here, not by
  # nixpkgs. nixpkgs updates will NOT touch this package. To bump: update
  # version/src hash (+ apiDeps/extensionManagerDeps) and re-verify that all
  # patches apply (git clone --branch v<X> ... && patch -p1 --dry-run).
  vicinae =
    let
      src = prev.fetchFromGitHub {
        owner = "vicinaehq";
        repo = "vicinae";
        tag = "v0.29.0";
        hash = "sha256-+Ti1hcYdjgdAZWu5f6myDckjp7ox0mtux7q8U1t44jo=";
      };
    in
    prev.vicinae.overrideAttrs (old: {
      version = "0.29.0";
      inherit src;
      # Tab/Shift+Tab walk the item list (launcher-menu style: grids step
      # across a row and spill onto the next one), work window-wide via a
      # fallback in LauncherWindow, navigate the open action stack, accept the
      # highlighted completion and keep an emacs kill ring in the search input
      # (C-d/C-k/C-u/C-w/C-y); Ctrl+C dismisses. The keybinding patch makes the
      # list navigation chords hybrid — emacs C-n/C-p/C-Alt-b/f and vim
      # C-j/C-k/C-h/C-l both work in one launcher. The QML patches target the
      # LauncherPage's view (root.commandView), not the page wrapper — ported
      # to v0.29.0. The dmenu patch keeps
      # the `vicinae dmenu` picker alive across focus changes and resolves the
      # CLI request when the window closes (upstream issue #1827). The lusty
      # patch ranks the root search with the lusty-fuzzy crate's matcher
      # (ported to src/lib/fuzzy/include/fuzzy/lusty.hpp) instead of fzf's v2
      # scorer, so the pickers, the tray and the launcher rank identically.
      patches = (old.patches or [ ]) ++ [
        ./vicinae-tab-qml.patch
        ./vicinae-hybrid-keys.patch
        ./vicinae-dmenu-fix.patch
        ./vicinae-lusty-search.patch
      ];
      apiDeps = prev.fetchNpmDeps {
        src = "${src}/src/typescript/api";
        hash = "sha256-4FEaBDJK9abcgz+vptuL4wQ8zhp+wpLbbR4Y79BVhEg=";
      };
      extensionManagerDeps = prev.fetchNpmDeps {
        src = "${src}/src/typescript/extension-manager";
        hash = "sha256-pEgqFgvdz7Bcc+LznCI+KlD1XEfUuWFWjS24MJ7sx3k=";
      };
      cmakeFlags =
        builtins.filter (f: f != "-DINSTALL_BROWSER_NATIVE_HOST:STRING=OFF") (old.cmakeFlags or [ ])
        ++ [ "-DINSTALL_BROWSER_NATIVE_HOST:STRING=ON" ];
    });

}
