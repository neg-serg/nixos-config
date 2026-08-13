{ lib, mkBool, ... }:
with lib;
{
  options.features.dev = {
    enable = mkBool "enable Dev stack (toolchains, editors, hack tooling)" true;
    ai = {
      enable = mkBool "enable AI tools (e.g., LM Studio)" true;
      omp.enable = mkBool "install Oh My Pi (omp) AI coding agent (fork of Pi)" false;
    };
    pkgs = {
      iac = mkBool "enable infrastructure-as-code tooling (Terraform, etc.)" true;
      joern = mkBool "enable Joern code analysis platform" true;
    };
    rust = {
      enable = mkBool "enable Rust tooling (rustup, rust-analyzer)" true;
    };
    cpp = {
      enable = mkBool "enable C/C++ tooling (gcc/clang, cmake, ninja, lldb)" true;
    };
    haskell = {
      enable = mkBool "enable Haskell tooling (ghc, cabal, stack, HLS)" true;
    };
    java = {
      enable = mkBool "enable Java/JVM development tooling (JDK, Maven)" false;
      maven = mkBool "enable Apache Maven build tool" true;
    };
    python = {
      core = mkBool "enable core Python development packages" true;
      tools = mkBool "enable Python tooling (LSP, utilities)" true;
    };

    unreal = {
      enable = mkBool "enable Unreal Engine 5 tooling" false;
      root = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''Checkout directory for Unreal Engine sources. Defaults to "~/games/UnrealEngine".'';
        example = "/mnt/storage/UnrealEngine";
      };
      repo = mkOption {
        type = types.str;
        default = "git@github.com:EpicGames/UnrealEngine.git";
        description = "Git URL used by ue5-sync (requires EpicGames/UnrealEngine access).";
      };
      branch = mkOption {
        type = types.str;
        default = "5.4";
        description = "Branch or tag to sync from the Unreal Engine repository.";
      };
      useSteamRun = mkOption {
        type = types.bool;
        default = true;
        description = "Wrap Unreal Editor launch via steam-run to provide FHS runtime libraries.";
      };
    };
    bpf.enable = mkBool "enable BPF tracing tools (bpftrace, below)" false;
  };

}
