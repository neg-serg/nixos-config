{
  lib,
  pkgs,
}: let
  devNixTools = [
    pkgs.alejandra # Nix formatter
    pkgs.age # modern encryption tool (for sops)
    pkgs.deadnix # find dead Nix code
    pkgs.git-absorb # autosquash fixups into commits
    pkgs.gitoxide # fast Rust Git tools
    pkgs.just # task runner
    pkgs.markdownlint-cli # Markdown linter/fixer
    pkgs.python3Packages.mdformat # Markdown formatter
    pkgs.nil # Nix language server
    pkgs.sops # secrets management
    pkgs.statix # Nix linter
    pkgs.treefmt # formatter orchestrator
  ];
  rustBaseTools = [
    pkgs.cargo # Rust build tool
    pkgs.rustc # Rust compiler
  ];
  # Preserve the availability-guarded helper semantics
  rustExtraTools =
    [
      pkgs.hyperfine # CLI benchmarking
      pkgs.kitty # terminal (for graphics/testing)
      pkgs.wl-clipboard # Wayland clipboard helpers
    ]
    ++ (
      let
        opt = path: items: lib.optionals (lib.hasAttrByPath path pkgs) items;
      in
        lib.concatLists [
          # Cross-building support for cargo-zigbuild
          (opt ["zig"] [pkgs.zig])
          # Common native deps helpers
          (opt ["pkg-config"] [pkgs.pkg-config])
          (opt ["openssl"] [pkgs.openssl pkgs.openssl.dev])
          # Useful cargo subcommands
          (opt ["cargo-nextest"] [pkgs.cargo-nextest])
          (opt ["cargo-audit"] [pkgs.cargo-audit])
          (opt ["cargo-deny"] [pkgs.cargo-deny])
          (opt ["cargo-outdated"] [pkgs.cargo-outdated])
          (opt ["cargo-bloat"] [pkgs.cargo-bloat])
          (opt ["cargo-modules"] [pkgs.cargo-modules])
          (opt ["cargo-zigbuild"] [pkgs.cargo-zigbuild])
          (opt ["bacon"] [pkgs.bacon])
        ]
    );
in {
  inherit devNixTools rustBaseTools rustExtraTools;
}
