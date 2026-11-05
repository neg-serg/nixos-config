##
# Module: llm/fim
# Purpose: Fill-in-the-middle completion server for editors — a dedicated
# llama.cpp instance with a small code model, kept out of llama-swap on
# purpose.
#
# Why a second server and not a llama-swap slot: every completion is a request,
# and llama-swap serializes models on the 16 GB card. Sharing the slot would
# evict the chat model on the first keystroke (a 12 GB reload) and re-load the
# coder on the first chat message.
#
# Why a *user* unit started by the editor: a resident 1.5B Q8 holds ~1.6 GB of
# VRAM, and the 26B/27B chat tiers already sit at the card's limit with the
# desktop open (modules/llm/llama-swap.nix). files/nvim/lua/plugins/completion/
# minuet.lua starts the unit on nvim startup and stops it when the last nvim
# exits, so the editor pays the ~1.5 s model load once per session and the chat
# stack gets the whole card at any other time.
#
# The model is Qwen2.5-Coder-1.5B-Instruct (Apache-2.0), Q8_0 GGUF from
# ggml-org on /zero. FIM tokens are applied by the client (minuet-ai.nvim):
# <|fim_prefix|>before<|fim_suffix|>after<|fim_middle|>.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  systemdUser = config.lib.neg.systemdUser;
  llamaVulkan = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";
  modelDir = "/zero/ai/llama";
in
{
  options.services.llama-fim = {
    # The unit is started by the editor, not by a target: default = true only
    # means "it exists", and it costs nothing until nvim asks for it.
    enable =
      lib.mkEnableOption ''
        llama-server FIM — fill-in-the-middle completion backend for
        Neovim (Qwen2.5-Coder-1.5B, Vulkan/RADV), a user unit started and
        stopped by the editor. Port 8012 by default.
      ''
      // {
        default = true;
      };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8012;
      description = "Port for the OpenAI-compatible completions endpoint (127.0.0.1).";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "${modelDir}/fim/qwen2.5-coder-1.5b-q8_0.gguf";
      description = "GGUF file to serve; downloaded manually to the zero pool.";
    };
  };

  config = lib.mkIf (enabled && config.services.llama-fim.enable) {
    # No wantedBy: the editor starts it (systemctl --user start llama-fim) on
    # nvim startup and stops it when the last nvim exits.
    systemd.user.services.llama-fim = systemdUser.mkUserService {
      presets = [ "restartOnFailure" ];
      description = "llama-server FIM (Qwen2.5-Coder 1.5B, editor autocompletion)";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        RestartSec = 5;
        ExecStart = ''
          ${llamaVulkan} --device Vulkan0 \
            -m ${config.services.llama-fim.model} \
            -ngl 99 -c 4096 -np 1 -ub 1024 -b 1024 \
            --flash-attn on --cache-reuse 256 \
            --host 127.0.0.1 --port ${toString config.services.llama-fim.port}
        '';
      };
    };
  };
}
