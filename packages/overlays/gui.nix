inputs: final: prev:
let
  callPkg = final.neg.functions.callPkg; # shared helper (functions.nix)
  pkg = final.neg.functions.pkg; # name → packages/<name>, no `../` counting
  # Shared builder for the install-as-is Vicinae extensions.
  mkVicinaeExtension = final.neg.functions.mkVicinaeExtension;
in
{
  # nixpkgs' hyprland wraps binutils, pciutils, pkgconf and hyprland-guiutils
  # into its runtime PATH (wrapRuntimeDeps). hyprland-guiutils is installed
  # system-wide anyway (modules/user/nix-maid/apps/gui-apps.nix), so keeping
  # the wrapper off saves the wrapper itself and three build-time tools in the
  # compositor's closure.
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
  # Waylandar is a standalone Quickshell calendar/dashboard; exposed as a flake
  # package so the system only carries an on-demand launcher.
  waylandar = callPkg (pkg "waylandar") { };
  # RustGIS — desktop GIS built from the prebuilt upstream release binaries
  # (~200 MB of ELF). Exposed here so the flake carries `.#rustgis` and the
  # system only installs an on-demand launcher
  # (modules/user/nix-maid/apps/gui-apps.nix).
  # Patched Vivaldi build (wayland flags, bundled libffmpeg RUNPATH); the system
  # only carries a launcher.
  vivaldi-fixed = callPkg (pkg "vivaldi") { };
  # hypr-kdeconnect-fix — RemoteDesktop portal backend bridging KDE Connect /
  # Deskflow input to the wlroots virtual-input protocols Hyprland exposes.
  # hyprqt6engine — not in the pinned nixpkgs yet, pinned locally (see
  # packages/hyprqt6engine). Qt6 platform theme + widget style for Hyprland;
  # the session selects it via QT_QPA_PLATFORMTHEME=hyprqt6engine and feeds it
  # ~/.config/hypr/hyprqt6engine.conf (modules/user/nix-maid/gui/qt.nix).
  wl = callPkg (pkg "wl") { };
  wl-switcher = callPkg (pkg "wl-switcher") { inherit mkVicinaeExtension; };
  wallhaven = callPkg (pkg "wallhaven") { inherit mkVicinaeExtension; };
  hyprwhspr = callPkg (pkg "hyprwhspr") { inherit mkVicinaeExtension; };
  aura = callPkg (pkg "aura") { inherit mkVicinaeExtension; }; # the emotion/CBT diary: record a note from the launcher
  sonda = callPkg (pkg "sonda") { }; # file manager for pleamar-wm that searches files by what they hold
  # Irori — game launcher repacked from the upstream release tarball. The
  # WebKitGTK sign-in helper makes the closure heavy, so the system installs the
  # on-demand launcher (modules/user/games/irori.nix) instead of the package.

  # ArtCraft suite: the apps are on-demand roots
  # (modules/user/nix-maid/apps/craft-apps.nix) built on first launch, so the
  # system generation carries launchers and desktop entries only. VectorCraft,
  # SoundCraft, DeckCraft, GridCraft, WordCraft and the shared `craft-fonts`
  # bundle come from nixpkgs now — its recipes are newer than the local copies
  # used to be (the 2026-11-21 nixpkgs bump inverted the gap). FigCraft,
  # SolidCraft and Craft Anything are still built here: nixpkgs has no recipe.

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
        tag = "v0.30.0";
        hash = "sha256-uZYp/eYUhO9udRfE2hLf/+zl4tEY49EzqBwH5IH8BF8=";
      };
    in
    prev.vicinae.overrideAttrs (old: {
      version = "0.30.0";
      inherit src;
      # Tab/Shift+Tab walk the item list (launcher-menu style: grids step
      # across a row and spill onto the next one), work window-wide via a
      # fallback in LauncherWindow, navigate the open action stack, accept the
      # highlighted completion and keep an emacs kill ring in the search input
      # (C-d/C-k/C-u/C-w/C-y); Ctrl+C dismisses. The keybinding patch makes the
      # list navigation chords hybrid — emacs C-n/C-p/C-Alt-b/f and vim
      # C-j/C-k/C-h/C-l both work in one launcher. The QML patches target the
      # LauncherPage's view (root.commandView), not the page wrapper — ported
      # to v0.30.0 (SearchBar's dismiss goes through Launcher.nav; the generic
      # `Nav` singleton no longer exists). The dmenu patch keeps
      # the `vicinae dmenu` picker alive across focus changes and resolves the
      # CLI request when the window closes (upstream issue #1827). The lusty
      # patch ranks the root search with the lusty-fuzzy crate's matcher
      # (ported to src/lib/fuzzy/include/fuzzy/lusty.hpp) instead of fzf's v2
      # scorer, so the pickers, the tray and the launcher rank identically.
      # The clipboard patch keeps the selection a paste from the history just
      # wrote on the clipboard: upstream restores the previous selection 800 ms
      # later, so a second paste yields the old content (vicinaehq/vicinae#2133).
      patches = (old.patches or [ ]) ++ [
        ./vicinae-tab-qml.patch
        ./vicinae-hybrid-keys.patch
        ./vicinae-dmenu-fix.patch
        ./vicinae-lusty-search.patch
        ./vicinae-clipboard-paste-restore.patch
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
