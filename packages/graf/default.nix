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

  # Local patch: relative markdown links as graph edges. Upstream builds the
  # graph from `[[wikilinks]]` only, resolved against note titles, so a vault
  # that links with `[text](../note.md)` collapses to the few notes carrying a
  # wikilink — 3 nodes / 2 edges on ~/notes, out of 568 scanned files. With the
  # patch the same vault yields 515 linked notes / 2053 edges. The patch also
  # skips fenced blocks and inline code spans for both syntaxes, because
  # upstream's regexes read documentation examples (`[[listenbrainz]]` in a TOML
  # snippet) as real links. Regenerate against a new upstream tag by applying
  # the same commit on a clone and re-running `git format-patch -1`; drop it
  # once upstream parses markdown links itself.
  patches = [ ./md-links.patch ];

  meta = lib.mkMeta {
    description = "Terminal-based force-directed graph visualizer for markdown wikilinks";
    homepage = "https://github.com/reekta92/graf";
    license = lib.licenses.gpl3Only;
    mainProgram = "graf";
  };
}
