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
    # Most LLM CLI tools (aichat, aider-chat, codex) live in dev shells
    pkgs.voxinput # voice→text via LocalAI/OpenAI + dotool/uinput (system-level utility)
  ];
}
