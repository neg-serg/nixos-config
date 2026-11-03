{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

# lazytail: terminal log viewer (ratatui) with live filtering and follow mode.
#
# Built from the neg-serg fork (https://github.com/neg-serg/lazytail) because
# upstream v0.10.0 still hard-codes every chord and reads `renderers:` from a
# project config only. The fork is upstream master plus three local commits:
#
#   keymap   configurable key bindings from `keys:` in lazytail.yaml — the `?`
#            overlay renders the live chords, plus ctrl+d/u half-page scrolling
#            and the F/h aliases. Upstream's ROADMAP still lists "Keybindings
#            config via lazytail.yaml" as open; drop this commit only after it
#            lands there.
#   stream   flush a partial batch of a live pipe after 100 ms of silence.
#            Otherwise `sudo dmesg -w | lazytail`, `journalctl -f` and the
#            teardown scratchpad tab stay empty until 10 000 lines pile up.
#   config   load renderer presets from the global config as well (project
#            presets shadow them by name) and compile them in
#            `lazytail config validate`/`show`.
#
# The fork also carries the post-v0.10.0 upstream commits (docs, musl CI and
# installer, nightly workflow, Rust 1.97 clippy fixes), so the package version
# is marked unstable until the next upstream release.
#
# The default feature set includes the MCP server (tokio + rmcp), which is what
# makes the viewer drivable from an agent, while `self_update` stays off — it
# would pull rustls/ring for an updater that Nix replaces anyway.
#
# Bump: commit and push ~/src/lazytail-work, then set `rev` here and refresh the
# hash with:
#   nix store prefetch-file --unpack --json \
#     https://github.com/neg-serg/lazytail/archive/<rev>.tar.gz
# Keep `cargoHash` unless Cargo.lock changes.
rustPlatform.buildRustPackage rec {
  pname = "lazytail";
  version = "0.10.0-unstable-2026-11-03";

  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "lazytail";
    rev = "3ecf9eaa0c71204e3a5bc8ac57666eaacde56f2e";
    hash = "sha256-bqR11+Tw5vFkg/Wv7UVZZC/LCHRP8HXZzzEXdZp31VY=";
  };

  cargoHash = "sha256-ZGt+iGeAqHF9ZQEyKjHwmmgCku4hFJnzeI65WzQDoSo=";

  # Kept off: the in-tree tests compile and pass (772 passed, 57 ignored on
  # 2026-11-03), but the watcher tests sleep on wall-clock time and flake
  # inside the build sandbox. `cargo test` is run by hand before bumping.
  doCheck = false;
  meta = lib.mkMeta {
    description = "Terminal log viewer with live filtering, follow mode and an MCP server";
    homepage = "https://github.com/raaymax/lazytail";
    license = lib.licenses.mit;
    mainProgram = "lazytail";
  };
}
