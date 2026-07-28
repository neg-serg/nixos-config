{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ollama;
in
{
  imports =
    let
      excludes = [ "open-webui.nix" ]; # disabled — not wired yet
    in
      builtins.readDir ./.
      |> builtins.attrNames
      |> builtins.filter (n: n != "default.nix" && !builtins.elem n excludes)
      |> map (n: ./. + "/${n}");
  config = lib.mkMerge [
    {
      services.ollama = {
        enable = lib.mkDefault true;
        package = pkgs.ollama-rocm;
        models = "/zero/llm/ollama-models";
      };
    }
    (lib.mkIf cfg.enable {
      systemd.tmpfiles.rules = [
        "d /zero/llm 0750 ollama ollama -"
        "d /zero/llm/ollama-models 0750 ollama ollama -"
      ];
      users.groups.ollama = { };
      users.users.ollama = {
        isSystemUser = true;
        group = "ollama";
        home = "/zero/llm/ollama-models";
        createHome = true;
      };
    })
  ];
}
