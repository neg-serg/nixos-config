{
  pkgs,
  lib,
  config,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  # stable-diffusion.cpp (Vulkan) T2I on RX 9070 XT; CLI binary is `sd-cli`
  sd-cpp = pkgs.stable-diffusion-cpp.override { vulkanSupport = true; };
in
{
  environment.systemPackages = lib.optionals enabled [
    # Most LLM CLI tools (aichat, aider-chat, codex) live in dev shells
    pkgs.voxinput # voice→text via LocalAI/OpenAI + dotool/uinput (system-level utility)
    sd-cpp # T2I via Vulkan (RADV); models in /zero/ai/image
  ];
}
