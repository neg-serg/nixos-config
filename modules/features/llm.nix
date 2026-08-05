{ lib, mkBool, ... }:
with lib;
{
  options.features.llm = {
    enable = mkBool "enable LLM stack (Ollama, Colibri, Open WebUI)" false;
  };
}
