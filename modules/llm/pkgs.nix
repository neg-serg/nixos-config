{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.aichat # Use GPT-4(V), Gemini, LocalAI, Ollama, etc. in terminal
    pkgs.codex # lightweight coding agent that runs in your terminal
    pkgs.aider-chat # Aider CLI assistant
    pkgs.openai # Python client library for OpenAI API
    pkgs.voxinput # voice→text via LocalAI/OpenAI + dotool/uinput
  ];
}
