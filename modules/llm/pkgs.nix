{
  pkgs,
  lib,
  config,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
in
{
  environment.systemPackages = lib.optionals enabled [
    # Most LLM CLI tools (aichat, aider-chat, codex) live in dev shells
    pkgs.voxinput # voice→text via LocalAI/OpenAI + dotool/uinput (system-level utility)
    (pkgs.stable-diffusion-cpp.override { vulkanSupport = true; }) # T2I on RX 9070 XT via Vulkan (RADV); models in /zero/ai/image
  ];
}
