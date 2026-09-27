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

  # The binary builds, the test *target* does not: at v0.10.0 the in-tree tests
  # call IndexReader::with_timestamps, which the crate no longer exposes
  # ("no associated function named with_timestamps", src/reader/combined_reader.rs
  # :458/:461), so `cargo test` cannot compile — nothing to run. Checked on
  # 2026-09-26 against the v0.10.0 tarball; revisit on the next bump.
  doCheck = false;
  meta = lib.mkMeta {
    description = "Terminal log viewer with live filtering, follow mode and an MCP server";
    homepage = "https://github.com/raaymax/lazytail";
    license = lib.licenses.mit;
    mainProgram = "lazytail";
  };
}
