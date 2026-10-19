{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

# lazytail: terminal log viewer (ratatui) with live filtering and follow mode.
# Upstream builds one binary; the default feature set includes the MCP server
# (tokio + rmcp), which is what makes the viewer drivable from an agent, while
# `self_update` stays off — it would pull rustls/ring for an updater that Nix
# replaces anyway.
rustPlatform.buildRustPackage rec {
  pname = "lazytail";
  version = "0.10.0";

  src = fetchFromGitHub {
    owner = "raaymax";
    repo = "lazytail";
    tag = "v${version}";
    hash = "sha256-BjQ7YkGttRK5EhApoJXw3FDNyH9okD721ZmW4T2U07U=";
  };

  cargoHash = "sha256-ZGt+iGeAqHF9ZQEyKjHwmmgCku4hFJnzeI65WzQDoSo=";

  # Local patch: configurable key bindings. Upstream v0.10.0 hard-codes every
  # chord in src/handlers/input.rs (it is still a roadmap item upstream:
  # "Keybindings config via lazytail.yaml"), so the `keys:` section in
  # files/lazytail/config.yaml would be ignored without this. The patch turns
  # that table into a keymap with the upstream chords as defaults, adds
  # ctrl+d/ctrl+u half-page scrolling and the `F`/`h` aliases, validates the
  # section in `lazytail config validate`, and makes the `?` overlay render the
  # live chords. Regenerate against a new upstream tag with `git format-patch`
  # from the fork copy; drop the patch once upstream ships the feature.
  #
  # Second local patch: live pipes. v0.10.0 flushes `cmd | lazytail` output only
  # once STREAM_BATCH_SIZE (10 000) lines have piled up or the stream ends, so a
  # follow-style pipe — `sudo dmesg -w | lazytail`, `journalctl -f`, the teardown
  # scratchpad tab in files/kitty/teardown.session — stayed empty forever. The
  # patch flushes a partial batch after 100 ms of silence and splits lines on
  # raw bytes, so a multi-byte character across two reads is no longer mangled.
  #
  # Third local patch: global renderers. v0.10.0 reads `renderers:` from a
  # project lazytail.yaml only, so a renderer preset could not live next to the
  # global `sources:`/`keys:`/`theme:` it belongs to (files/lazytail/config.yaml).
  # The patch loads presets from the global config too — project presets shadow
  # them by name — and teaches `lazytail config validate`/`show` about them.
  patches = [
    ./keymap.patch
    ./stream-flush.patch
    ./global-renderers.patch
  ];

  # Kept off: the in-tree tests do compile and pass at v0.10.0 (783 tests on
  # 2026-10-18 — the older note about IndexReader::with_timestamps is stale),
  # but the watcher tests sleep on wall-clock time and flake inside the build
  # sandbox. `cargo test` is run by hand before bumping.
  doCheck = false;
  meta = lib.mkMeta {
    description = "Terminal log viewer with live filtering, follow mode and an MCP server";
    homepage = "https://github.com/raaymax/lazytail";
    license = lib.licenses.mit;
    mainProgram = "lazytail";
  };
}
