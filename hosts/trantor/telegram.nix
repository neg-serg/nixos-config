{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
# Shared Telegram notification stack for trantor.
#
# The two SOPS secrets and the `telegram-send` wrapper live here exactly once;
# the alert/notify units and scripts (services/telegram-units.nix, notify-*.nix,
# the pill stack) consume config.trantor.telegram.{sender,botTokenPath,chatIdPath} instead
# of redeclaring the secrets and re-implementing the socks-proxy curl retry.
#
# api.telegram.org is only reachable through the user sing-box socks proxy
# (127.0.0.1:10808), which starts at login, so the wrapper retries with 5s
# pauses up to `attempts` (default 12).
let
  secretsPresent = builtins.pathExists (inputs.self + "/secrets/telegram.sops.yaml");

  botToken = config.sops.secrets."telegram/bot-token".path;
  chatId = config.sops.secrets."telegram/chat-id".path;
in
{
  options.trantor.telegram = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = secretsPresent;
      defaultText = lib.literalExpression ''builtins.pathExists (inputs.self + "/secrets/telegram.sops.yaml")'';
      description = ''
        Enable the trantor Telegram notification stack (secrets + shared sender).
        Defaults to whether secrets/telegram.sops.yaml exists, so a checkout
        without the SOPS secrets stays inert instead of failing activation.
      '';
    };

    sender = lib.mkOption {
      type = lib.types.package;
      description = ''
        `telegram-send` wrapper. Plain form: `telegram-send <msg> [detail]
        [attempts]`; HTML form: `telegram-send --html-file <path|-> [attempts]`,
        which posts with parse_mode=HTML and splits a body over the Bot API
        4096-character limit between lines, falling back to plain text if the
        markup is rejected. Both forms go from the SOPS secrets through the
        local sing-box socks proxy, retrying up to <attempts> (default 6)
        times with 5s pauses and a 5s connect / 15s total timeout per attempt.
      '';
    };

    botTokenPath = lib.mkOption {
      type = lib.types.str;
      description = "Decrypted Telegram bot token path (owner root, mode 0400).";
    };

    chatIdPath = lib.mkOption {
      type = lib.types.str;
      description = "Decrypted Telegram chat id path (owner root, mode 0400).";
    };

    llmEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:9292";
      description = ''
        OpenAI-compatible base URL of the local model stack used for free-text
        answers in the Telegram chat. Loopback only: the monitoring snapshot
        and the question stay on the host.
      '';
    };

    llmModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen3.8-27b-abliterated";
      description = ''
        llama-swap model answering questions in the chat — general ones
        included, with the host snapshot as extra context. The default is the
        quality tier (~30 tok/s, 13.75 GiB with the desktop): it answers
        general knowledge far more reliably than the 8B vision tier, costs
        10-20 s on a cold load and unloads after 60 s idle. A smaller tier is
        faster and leaves more VRAM to the desktop.
      '';
    };
  };

  config = lib.mkIf config.trantor.telegram.enable {
    sops.secrets."telegram/bot-token" = {
      sopsFile = config.lib.neg.path "secrets/telegram.sops.yaml";
      key = "bot-token";
      owner = "root";
      mode = "0400";
    };
    sops.secrets."telegram/chat-id" = {
      sopsFile = config.lib.neg.path "secrets/telegram.sops.yaml";
      key = "chat-id";
      owner = "root";
      mode = "0400";
    };

    trantor.telegram.botTokenPath = botToken;
    trantor.telegram.chatIdPath = chatId;

    trantor.telegram.sender = pkgs.writeShellApplication {
      name = "telegram-send";
      runtimeInputs = [
        pkgs.curl # HTTP(S) client for the Telegram Bot API
        pkgs.coreutils # date, seq, sleep for the retry loop and timestamps
        pkgs.gnused # strip_html: the plain-text fallback for rejected markup
      ];
      text = builtins.readFile (
        pkgs.replaceVars ./telegram/send.sh {
          inherit botToken chatId;
        }
      );

    };
  };
}
