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
  # hyprland-guiutils — not in the pinned nixpkgs yet, pinned locally (see
  # packages/hyprland-guiutils). It supersedes hyprland-qtutils and ships the
  # same five binaries (hyprland-dialog, -donate-screen, -update-screen,
  # -welcome, -run), so installing both would collide in the system profile.
  hyprland-guiutils = callPkg (pkg "hyprland-guiutils") { };
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

  # pleamar — Wayland desktop shell runtime (bars, launchers, notification
  # centres, docks, lock screens as animated scenes). Rev-pinned input in
  # flake.nix; nixpkgs follows the top-level pin so the Rust build reuses the
  # cached toolchain closure.
  pleamar = inputs.pleamar.packages.${prev.stdenv.hostPlatform.system}.pleamar;

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
