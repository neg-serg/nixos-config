{
  description = "Rust project scaffold with crane, unified toolchain, and checks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
    advisory-db.url = "github:rustsec/advisory-db";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      rust-overlay,
      crane,
      advisory-db,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
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
          nativeBuildInputs = [ rustToolchain ];
        };
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        # Avoid duplicate test runs here; nextest is wired via checks.
        app = craneLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;
            doCheck = false;
          }
        );
      in
      {
        packages.default = app;

        checks = {
          build = app;
          clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "-- -D warnings";
            }
          );
          fmt = craneLib.cargoFmt { inherit src; };
          doc = craneLib.cargoDoc (commonArgs // { inherit cargoArtifacts; });
          audit = craneLib.cargoAudit { inherit src advisory-db; }; # offline DB
          deny = craneLib.cargoDeny { inherit src; };
          nextest = craneLib.cargoNextest (commonArgs // { inherit cargoArtifacts; });
        };

        apps.default = {
          type = "app";
          program = "${app}/bin/${pname}";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            rustToolchain
            pkgs.pkg-config # Tool that allows packages to find out information about o...
            pkgs.openssl # Cryptographic library that implements the SSL and TLS pro...
            pkgs.cargo-nextest # Next-generation test runner for Rust projects
            pkgs.cargo-audit # Audit Cargo.lock files for crates with security vulnerabi...
            pkgs.cargo-deny # Cargo plugin for linting your dependencies
            pkgs.cargo-outdated # Cargo subcommand for displaying when Rust dependencies ar...
            pkgs.cargo-bloat # Tool and Cargo subcommand that helps you find out what ta...
            pkgs.cargo-modules # Cargo plugin for showing a tree-like overview of a crate'...
            pkgs.cargo-zigbuild # Tool to compile Cargo projects with zig as the linker
            pkgs.zig # General-purpose programming language and toolchain for ma...
            pkgs.bacon
          ];
          RUST_BACKTRACE = "1";
        };
      }
    );
}
