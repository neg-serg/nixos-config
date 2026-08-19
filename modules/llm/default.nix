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
    |> builtins.map (n: ./. + "/${n}");
  config = lib.mkIf (config.lib.neg.enabled "llm") (
    lib.mkMerge [
      {
        services.ollama = {
          enable = lib.mkDefault true;
          package = pkgs.ollama-rocm;
          # RX 9070 XT (Navi 48, gfx1201) — native ROCm support, no override
          user = "ollama";
          group = "ollama";
          models = "/zero/ai/ollama"; # existing 413G model store on the zero pool
        };

        # Recursively fix ownership of the existing model store for the ollama
        # service user, and keep the main user in the ollama group so neg can
        # still manage model files.
        systemd.tmpfiles.rules = [
          "d /zero/ai 0755 root root -"
          "d /zero/ai/ollama 0770 ollama ollama -"
          "Z /zero/ai/ollama 0770 ollama ollama -"
          # llama-server (qwen3-vl GGUF) model store — main user manages files
          "d /zero/ai/llama 0755 ${config.users.main.name} ${config.users.main.name} -"
        ];
        # tmpfiles refuses paths under /zero/ai: /zero is owned by neg, so the
        # neg→root transition trips systemd's unsafe-path check and the rules
        # are skipped silently. Create the dirs via activation instead.
        system.activationScripts.ai-model-dirs = lib.stringAfter [ "users" ] ''
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/image
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/embeddings
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/glm52_i4
          # music AI models (AMT weights, basic-pitch ONNX) — main user manages files
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/music
        '';
        users.users."${config.users.main.name}".extraGroups = lib.mkAfter [ "ollama" ];
      }
      (lib.mkIf cfg.enable {
        # nixpkgs sets DynamicUser=true unconditionally even with a static
        # user; force it off so the process runs as the real ollama user and
        # keeps stable ownership of /zero/ai/ollama.
        systemd.services.ollama.serviceConfig.DynamicUser = lib.mkForce false;
      })
    ]
  );
}
