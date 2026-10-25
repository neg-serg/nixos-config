{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "dnsglobe";
  version = "0.5.0";

  # Not in nixpkgs (checked against the pinned nixpkgs). Upstream ships its own
  # flake with the same buildRustPackage shape; this copy keeps the pin in-tree
  # so the flake does not depend on an upstream ref.
  src = fetchFromGitHub {
    owner = "514-labs";
    repo = "dnsglobe";
    rev = "v${version}";
    hash = "sha256-c5H7i7ElWj4lbzDe4+l2av87HndvCHzr8QpQgcKDLGg=";
  };

  # Dependencies (ratatui, crossterm, hickory-resolver, tokio, clap, serde) are
  # all mainstream crates; Cargo.lock is committed upstream.
  cargoHash = "sha256-1h8zBS81hNbnYyLiqyqTQRnAaiB5t0SFnqxasAPV6DQ=";

  # The only network traffic is the point of the tool: it queries the public
  # DNS resolvers listed in its config (34 built-ins) for one record and draws
  # the answers on a world map. No telemetry, no upload, no install scripts.
  meta = {
    description = "Global DNS propagation checker TUI — watch a DNS record propagate across public resolvers on a world map";
    homepage = "https://github.com/514-labs/dnsglobe";
    changelog = "https://github.com/514-labs/dnsglobe/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "dnsglobe";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    maintainers = [ ];
  };
}
