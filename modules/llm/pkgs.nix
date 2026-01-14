{ pkgs, ... }:
{
  environment.systemPackages = [

    # Most LLM CLI tools moved to devShells.ai (aichat, aider-chat, codex, openai)
    pkgs.voxinput # voice→text via LocalAI/OpenAI + dotool/uinput (system-level utility)
  ];
}
