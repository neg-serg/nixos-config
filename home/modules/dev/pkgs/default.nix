{
  lib,
  pkgs,
  config,
  ...
}: let
  groups = rec {
    formatters = [
      pkgs.shfmt # shell script formatter
      pkgs.black # Python formatter
      pkgs.stylua # Lua code formatter
    ];
    analyzers = [
      pkgs.flawfinder # examine C/C++ code for security flaws
      pkgs.ruff # Python linter
      pkgs.shellcheck # shell linter
      pkgs.mypy # optional static typing checker for Python
      pkgs.codeql # CodeQL CLI for code analysis
    ];
    codecount = [
      pkgs.cloc # count lines of code
      pkgs.scc # fast, parallel code counter
      pkgs.tokei # blazingly fast code counter
    ];
    radicle = [
      pkgs.radicle-node # Radicle server/node
      pkgs.radicle-explorer # Web frontend for Radicle
    ];
    runtime = [
      pkgs.nodejs_24 # Node.js runtime (npm/yarn tooling)
    ];
    misc = [
      pkgs.deheader # remove unneeded C/C++ includes
    ];

    # Haskell toolchain and related tools
    haskell =
      [
        pkgs.ghc # Haskell compiler
        pkgs.cabal-install # Haskell package/build tool
        pkgs.stack # alternative Haskell build tool
        pkgs.haskell-language-server # Haskell LSP for IDEs
        pkgs.hlint # Haskell linter
        pkgs.ormolu # Haskell formatter
        pkgs.ghcid # fast GHCi-based reloader
      ]
      # Some Haskell tools may be unavailable on a given nixpkgs pin — include conditionally.
      ++ (lib.optionals (pkgs ? fourmolu) [pkgs.fourmolu]) # alt formatter
      ++ (lib.optionals (pkgs ? hindent) [pkgs.hindent]); # alt formatter

    # Rust toolchain and helpers
    rust = [
      pkgs.rustup # flexible Rust toolchain manager (stable/nightly components)
    ];

    # C/C++ toolchain and common build tools
    cpp = [
      pkgs.gcc # GCC toolchain
      pkgs.clang # Clang/LLVM C/C++ compiler
      pkgs.clang-tools # clangd + clang-tidy + extras
      pkgs.cmake # CMake build system
      pkgs.ninja # Ninja build tool
      pkgs.bear # compilation database generator (compile_commands.json)
      pkgs.ccache # compiler cache
      pkgs.lldb # LLVM debugger
    ];

    # IaC backend package (Terraform or OpenTofu) controlled by
    # features.dev.iac.backend (default: "terraform").
    iac = let
      backend = config.features.dev.iac.backend or "terraform";
      main =
        if backend == "tofu"
        then pkgs.opentofu
        else pkgs.terraform;
    in
      [
        main # IaC backend (Terraform/OpenTofu)
        pkgs.ansible # configuration management tool
      ]
      # AI-assisted IaC generator (Firefly's aiac), only if available in pinned nixpkgs
      ++ (lib.optionals (pkgs ? aiac) [pkgs.aiac]);
  };
in
  lib.mkIf config.features.dev.enable {
    home.packages = let
      flags =
        (config.features.dev.pkgs or {})
        // {
          haskell = config.features.dev.haskell.enable or false;
          rust = config.features.dev.rust.enable or false;
          cpp = config.features.dev.cpp.enable or false;
        };
    in
      config.lib.neg.pkgsList (
        config.lib.neg.mkEnabledList flags groups
      );

    features.allowUnfree.extra = lib.optionals (config.features.dev.pkgs.analyzers or false) [
      "codeql"
    ];
  }
