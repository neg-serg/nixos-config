{
  config,
  lib,
  ...
}: let
  cfg = config.services.ollama;
in {
  imports = [
    ./pkgs.nix
    ./codex-config.nix
  ];
  config = lib.mkMerge [
    {
      services.ollama = {
        enable = lib.mkDefault true;
        acceleration = "rocm";
        models = "/zero/llm/ollama-models";
      };
    }
    (lib.mkIf cfg.enable {
      systemd.tmpfiles.rules = [
        "d /zero/llm 0750 ollama ollama -"
        "d /zero/llm/ollama-models 0750 ollama ollama -"
      ];
      users.groups.ollama = {};
      users.users.ollama = {
        isSystemUser = true;
        group = "ollama";
        home = "/zero/llm/ollama-models";
        createHome = true;
      };
    })
  ];
}
