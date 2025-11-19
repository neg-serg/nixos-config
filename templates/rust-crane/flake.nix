{
  description = "Rust project scaffold with crane, unified toolchain, and checks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
    advisory-db.url = "github:rustsec/advisory-db";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    rust-overlay,
    crane,
    advisory-db,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      overlays = [(import rust-overlay)];
      pkgs = import nixpkgs {
        inherit system overlays;
        config.allowAliases = false;
      };

      # Use the same toolchain as rustup via rust-toolchain.toml
      rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
      craneLib = crane.mkLib pkgs;
      src = craneLib.cleanCargoSource (craneLib.path ./.);

      pname = "app";
      version = "0.1.0";
      commonArgs = {
        inherit pname version src;
        nativeBuildInputs = [rustToolchain];
      };
      cargoArtifacts = craneLib.buildDepsOnly commonArgs;
      # Avoid duplicate test runs here; nextest is wired via checks.
      app = craneLib.buildPackage (commonArgs
        // {
          inherit cargoArtifacts;
          doCheck = false;
        });
    in {
      packages.default = app;

      checks = {
        build = app;
        clippy = craneLib.cargoClippy (commonArgs
          // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "-- -D warnings";
          });
        fmt = craneLib.cargoFmt {inherit src;};
        doc = craneLib.cargoDoc (commonArgs // {inherit cargoArtifacts;});
        audit = craneLib.cargoAudit {inherit src advisory-db;}; # offline DB
        deny = craneLib.cargoDeny {inherit src;};
        nextest = craneLib.cargoNextest (commonArgs // {inherit cargoArtifacts;});
      };

      apps.default = {
        type = "app";
        program = "${app}/bin/${pname}";
      };

      devShells.default = pkgs.mkShell {
        packages = [
          rustToolchain
          pkgs.pkg-config
          pkgs.openssl
          pkgs.cargo-nextest
          pkgs.cargo-audit
          pkgs.cargo-deny
          pkgs.cargo-outdated
          pkgs.cargo-bloat
          pkgs.cargo-modules
          pkgs.cargo-zigbuild
          pkgs.zig
          pkgs.bacon
        ];
        RUST_BACKTRACE = "1";
      };
    });
}
