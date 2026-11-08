{
  pkgs,
  lib,
  config,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  onDemand = config.lib.neg.onDemand pkgs;

  llmctl = pkgs.writeShellApplication {
    name = "llmctl";
    runtimeInputs = [
      pkgs.python3
      pkgs.fzf # interactive model picker (`llmctl use`, `llmctl menu`)
    ];
    text = ''
      exec python3 ${./llmctl.py} "$@"
    '';
  };
in
{
  environment.systemPackages = lib.optionals enabled [
    # Most LLM CLI tools (aichat, aider-chat, codex) live in dev shells
    pkgs.voxinput # voice→text via LocalAI/OpenAI + dotool/uinput (system-level utility)
    (onDemand {
      name = "sd-cli";
      attr = "stable-diffusion-cpp";
    }) # T2I via Vulkan (RADV), built on demand; models in /zero/ai/image
    llmctl # local llama-swap control: status, model switching, chem/lean benches
  ];
}
