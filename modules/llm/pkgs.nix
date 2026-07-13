{
  pkgs,
  lib,
  config,
  ...
}:
let
  enabled = config.features.llm.enable or false;
in
{
  environment.systemPackages = lib.optionals enabled [
    # Most LLM CLI tools moved to devShells.ai (aichat, aider-chat, codex, openai)
    pkgs.voxinput # voice→text via LocalAI/OpenAI + dotool/uinput (system-level utility)
    # pkgs.ollama-vulkan # Ollama with Vulkan backend (alternative to CPU-only ollama)
  ];
}
