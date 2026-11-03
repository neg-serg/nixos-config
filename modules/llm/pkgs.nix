{
  pkgs,
  lib,
  config,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in
{
  environment.systemPackages = lib.optionals enabled [
    # Most LLM CLI tools (aichat, aider-chat, codex) live in dev shells
    pkgs.voxinput # voice→text via LocalAI/OpenAI + dotool/uinput (system-level utility)
    (onDemand {
      name = "sd-cli";
      attr = "stable-diffusion-cpp";
    }) # T2I via Vulkan (RADV), built on demand; models in /zero/ai/image
  ];
}
