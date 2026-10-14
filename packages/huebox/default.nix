{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

# huebox: terminal theme editor (ratatui TUI) with a live preview — it reads
# the colours the terminal actually uses, edits them in place, and pushes the
# palette back into the terminal config (kitty/ghostty/alacritty) line by line.
# The crate lives in the `rust/` subdirectory of the repo (the root carries the
# docs and the curl installer), so cargoRoot points there.
rustPlatform.buildRustPackage rec {
  pname = "huebox";
  version = "0.5.2";

  src = fetchFromGitHub {
    owner = "MikkelKappelPersson";
    repo = "huebox";
    tag = "v${version}";
    hash = "sha256-9VdzSLE+olzaeRSwPbjnERRi3U8WjY7Lld9YLWDvWkQ=";
  };

  cargoRoot = "rust";
  buildAndTestSubdir = "rust";
  cargoHash = "sha256-L/Z2bDQLdAfJ8TFsnmal8SyuL8++nm27IDLHcs/A3ag=";

  meta = lib.mkMeta {
    description = "Terminal theme editor with live preview";
    homepage = "https://github.com/MikkelKappelPersson/huebox";
    license = lib.licenses.mit;
    mainProgram = "huebox";
  };
}
