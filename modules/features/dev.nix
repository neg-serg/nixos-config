{ lib, mkBool, ... }:
{
  options.features.dev = {
    enable = mkBool "enable Dev stack (toolchains, editors, hack tooling)" true;
    pkgs = {
      # `iac` lived here until 2026-10-17: declared true everywhere and read by
      # nothing (no terraform/opentofu in the tree), so it only pretended to
      # gate tooling.
      joern = mkBool "enable Joern code analysis platform" true;
    };
    # Craft Anything: manual reverse-engineering workbench. The binaries are
    # on-demand launchers (modules/dev/craft-anything.nix), so enabling it
    # costs the system closure nothing until the first run.
    craftAnything.enable = mkBool "enable Craft Anything (reverse-engineering workbench + rebuild assistant)" false;
    ai = {
      enable = mkBool "enable AI tools (e.g., LM Studio)" true;
      herdr.enable = mkBool "install Herdr (terminal workspace manager / runtime for AI coding agents) with its neg config" false;
      rocm.enable = mkBool "install PyTorch with ROCm (gfx1201) + torch-rocm CLI for GPU fine-tuning" false;
    };
    rust = {
      enable = mkBool "enable Rust tooling (rustup, rust-analyzer)" true;
    };
    cpp = {
      enable = mkBool "enable C/C++ tooling (gcc/clang, cmake, ninja, lldb)" true;
    };
    java = {
      enable = mkBool "enable Java/JVM development tooling (Maven)" false;
      maven = mkBool "enable Apache Maven build tool" true;
    };
    python = {
      core = mkBool "enable core Python development packages" true;
      tools = mkBool "enable Python tooling (LSP, utilities)" true;
    };

    unreal = {
      enable = mkBool "enable Unreal Engine 5 tooling" false;
      useSteamRun = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Wrap Unreal Editor launch via steam-run to provide FHS runtime libraries.";
      };
    };
    # The Hub is a manual .deb install in ~/opt/unityhub; the module only ships
    # proxy-aware launchers (unityhub-proxy, unity-proxy) for it.
    unity = {
      enable = mkBool "enable proxy-aware Unity Hub / unity CLI launchers (requires features.net.proxy.enable)" false;
    };
    bpf.enable = mkBool "enable BPF tracing tools (bpftrace, below)" false;
  };

}
