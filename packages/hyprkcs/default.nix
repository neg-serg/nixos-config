##
# Package: hyprkcs
# Purpose: graphical keybind manager and cheat sheet for Hyprland (Rust +
#   GTK4): parses the keybind config, flags duplicate or broken binds and edits
#   them in place; the main window is a layer-shell overlay toggled from a
#   hotkey. Upstream tracks Hyprland's hyprlang configs only — Lua configs are
#   not parsed yet (kosa12/hyprKCS#77).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  gtk4-layer-shell,
  libxkbcommon,
}:

rustPlatform.buildRustPackage rec {
  pname = "hyprkcs";
  version = "1.25.6";

  # v1.25.6 (pinned to the commit the tag points at).
  src = fetchFromGitHub {
    owner = "kosa12";
    repo = "hyprKCS";
    rev = "ba77f586c6938de44c5395d595477808db153862";
    hash = "sha256-pvYgFd7WBlqT1+WJnuvRS5myT5dh6Difa/1hUJNEt5g=";
  };

  cargoHash = "sha256-xUrlRdW89FZ4A3SNdDw4Q8d6wJkCD8FtO8r4/8feRzc=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4 # GTK settings/schema env for the wrapped binary
  ];

  # gtk4-layer-shell turns the window into an overlay; libxkbcommon resolves
  # the key labels for the visual keyboard map (its xkb-config-root already
  # points into xkeyboard-config in this nixpkgs).
  buildInputs = [
    gtk4
    libadwaita
    gtk4-layer-shell
    libxkbcommon
  ];

  # buildRustPackage installs only the binary — upstream's Makefile also ships
  # the desktop entry and the scalable icon, which the launcher and the hotkey
  # path use.
  postInstall = ''
    install -Dm644 hyprkcs.desktop $out/share/applications/hyprkcs.desktop
    install -Dm644 assets/hyprkcs.svg $out/share/icons/hicolor/scalable/apps/hyprkcs.svg
  '';

  meta = lib.mkMeta {
    description = "Graphical Hyprland keybind manager and cheat sheet (GTK4 overlay)";
    homepage = "https://github.com/kosa12/hyprKCS";
    license = lib.licenses.gpl3Only;
    mainProgram = "hyprkcs";
  };
}
