{
  lib,
  pkgs,
  ...
}: let
  # Optional packages only available on some nixpkgs revisions.
  optionalHaskellTools =
    lib.optionals (pkgs ? fourmolu) [pkgs.fourmolu]
    ++ lib.optionals (pkgs ? hindent) [pkgs.hindent];
  optionalIaCTools = lib.optionals (pkgs ? aiac) [pkgs.aiac];
in {
  environment.systemPackages =
    lib.unique (
      [
        # Former base system dev helpers
        pkgs.just # command runner for project tasks
        pkgs.bacon # background rust code checker
        pkgs.bpftrace # trace events via eBPF
        pkgs.cutter # Rizin-powered reverse engineering UI
        pkgs.ddrescue # data recovery tool
        pkgs.evcxr # Rust REPL
        pkgs.foremost # recover files from raw disk data
        pkgs.freeze # render source files to images
        pkgs.gcc # GNU compiler collection
        pkgs.gdb # GNU debugger
        pkgs.hexyl # hexdump viewer
        pkgs.hyperfine # benchmarking tool
        pkgs.license-generator # CLI license boilerplates
        pkgs.lzbench # compression benchmark
        pkgs.pkgconf # pkg-config wrapper
        pkgs.plow # HTTP benchmarking tool
        pkgs.radare2 # command-line disassembler
        pkgs.strace # trace syscalls

        # Formatters and beautifiers
        pkgs.shfmt # shell formatter
        pkgs.black # Python formatter
        pkgs.stylua # Lua formatter

        # Static analysis and linters
        pkgs.flawfinder # C/C++ security scanner
        pkgs.ruff # Python linter
        pkgs.shellcheck # shell linter
        pkgs.mypy # Python type checker
        pkgs.codeql # GitHub CodeQL CLI for queries

        # Code counting/reporting utilities
        pkgs.cloc # count lines of code
        pkgs.scc # parallel code counter
        pkgs.tokei # fast code statistics

        # Radicle tooling
        pkgs.radicle-node # Radicle node/server
        pkgs.radicle-explorer # Radicle web explorer

        # General runtimes & helpers
        pkgs.nodejs_24 # Node.js runtime tooling
        pkgs.deheader # trim redundant C/C++ includes

        # Haskell toolchain
        pkgs.ghc # compiler
        pkgs.cabal-install # package/build tool
        pkgs.stack # alternative build tool
        pkgs.haskell-language-server # IDE/LSP backend
        pkgs.hlint # linter
        pkgs.ormolu # formatter
        pkgs.ghcid # fast GHCi reload loop

        # Rust toolchain
        pkgs.rustup # manage Rust channels/components

        # C/C++ companions
        pkgs.clang # LLVM compiler
        pkgs.clang-tools # clangd, clang-tidy, etc.
        pkgs.cmake # build system generator
        pkgs.ninja # fast build executor
        pkgs.bear # generate compile_commands.json
        pkgs.ccache # compiler cache
        pkgs.lldb # LLVM debugger

        # Infrastructure as code and automation
        pkgs.terraform # IaC backend (default)
        pkgs.opentofu # OpenTofu alternative backend
        pkgs.ansible # configuration management CLI
      ]
      ++ optionalHaskellTools
      ++ optionalIaCTools
    );
}
