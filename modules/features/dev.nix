{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.dev = {
    enable = mkBool "enable Dev stack (toolchains, editors, hack tooling)" true;
    ai = {
      enable = mkBool "enable AI tools (e.g., LM Studio)" true;
      antigravity.enable = mkBool "install Google Antigravity agentic IDE" false;
    };
    iac = {
      backend = mkOption {
        type = types.enum [
          "terraform"
          "tofu"
        ];
        default = "terraform";
        description = "Choose IaC backend: HashiCorp Terraform or OpenTofu (tofu).";
      };
    };
    pkgs = {
      formatters = mkBool "enable CLI/code formatters" true;
      codecount = mkBool "enable code counting tools" true;
      analyzers = mkBool "enable analyzers/linters" true;
      iac = mkBool "enable infrastructure-as-code tooling (Terraform, etc.)" true;
      radicle = mkBool "enable radicle tooling" true;
      runtime = mkBool "enable general dev runtimes (node etc.)" true;
      misc = mkBool "enable misc dev helpers" true;
    };
    hack = {
      core = {
        secrets = mkBool "enable git secret scanners" true;
        reverse = mkBool "enable reverse/disasm helpers" true;
        crawl = mkBool "enable web crawling tools" true;
      };
      forensics = {
        fs = mkBool "enable filesystem/disk forensics tools" true;
        stego = mkBool "enable steganography tools" true;
        analysis = mkBool "enable reverse/binary analysis tools" true;
        network = mkBool "enable network forensics tools" true;
      };
      pentest = mkBool "enable pentest tools" true;
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
    python = {
      core = mkBool "enable core Python development packages" true;
      tools = mkBool "enable Python tooling (LSP, utilities)" true;
    };
    emacs = {
      enable = mkBool "enable Emacs editor with org-babel config" false;
    };
    tla.enable = mkBool "enable TLA+ tooling (toolbox, formatter)" false;
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
    openxr = {
      enable = mkBool "enable OpenXR development stack" false;
      envision.enable = mkBool "install Envision UI for Monado" true;
      runtime = {
        enable = mkBool "install Monado OpenXR runtime" true;
        vulkanLayers.enable = mkBool "install Monado Vulkan layers" true;
        service.enable = mkBool "run monado-service as a user systemd service (graphical preset)" false;
      };
      tools = {
        motoc.enable = mkBool "install motoc (Monado Tracking Origin Calibration)" true;
        basaltMonado.enable = mkBool "install optional basalt-monado tools" false;
      };
    };
    bpf.enable = mkBool "enable BPF tracing tools (bpftrace, below)" false;
  };

  options.features.hack.enable = mkBool "enable Hack/security tooling stack" true;
}
