{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

# graf: terminal force-directed graph of markdown wikilinks (ratatui canvas +
# fdg-sim physics, petgraph backend). Upstream ships a flake of its own, but it
# pins an unpinned nixos-unstable ref and still declares 1.1.0, so the package
# is derived here from the release tag instead of following the flake input.
#
# Single binary, pure-Rust dependency tree (crossterm/ratatui/fdg-sim — no
# system libraries, no bindgen), so no nativeBuildInputs are needed. Runtime
# config is optional: defaults are compiled in, and `graf` only reads/writes
# ~/.config/graf/config.toml when the user asks for it (`--config`, Ctrl+R).
rustPlatform.buildRustPackage rec {
  pname = "graf";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "reekta92";
    repo = "graf";
    tag = "v${version}";
    hash = "sha256-4/r64u9PCtVf7UB3PW/yek8Oh+KNK2+a2mwYLkMEbBo=";
  };

  cargoHash = "sha256-6Pu3RZPT8KdHvvRLXPIDBVj8zebmnmCYSfHJjYALQVc=";

  meta = lib.mkMeta {
    description = "Terminal-based force-directed graph visualizer for markdown wikilinks";
    homepage = "https://github.com/reekta92/graf";
    license = lib.licenses.gpl3Only;
    mainProgram = "graf";
  };
}
