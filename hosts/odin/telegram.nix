{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
# Shared Telegram notification stack for odin.
#
# The two SOPS secrets and the `telegram-send` wrapper live here exactly once;
# the alert/notify units and scripts (services/telegram-units.nix, notify-*.nix,
# the pill stack) consume config.odin.telegram.{sender,botTokenPath,chatIdPath} instead
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
  options.odin.telegram = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = secretsPresent;
      defaultText = lib.literalExpression ''builtins.pathExists (inputs.self + "/secrets/telegram.sops.yaml")'';
      description = ''
        Enable the odin Telegram notification stack (secrets + shared sender).
        Defaults to whether secrets/telegram.sops.yaml exists, so a checkout
        without the SOPS secrets stays inert instead of failing activation.
      '';
    };

    sender = lib.mkOption {
      type = lib.types.package;
      description = ''
        `telegram-send <msg> [detail] [attempts]` wrapper: posts to the chat
        from the SOPS secrets through the local sing-box socks proxy, retrying
        up to <attempts> (default 12) times with 5s pauses.
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
  };

  config = lib.mkIf config.odin.telegram.enable {
    sops.secrets."telegram/bot-token" = {
      sopsFile = inputs.self + "/secrets/telegram.sops.yaml";
      key = "bot-token";
      owner = "root";
      mode = "0400";
    };
    sops.secrets."telegram/chat-id" = {
      sopsFile = inputs.self + "/secrets/telegram.sops.yaml";
      key = "chat-id";
      owner = "root";
      mode = "0400";
    };

    odin.telegram.botTokenPath = botToken;
    odin.telegram.chatIdPath = chatId;

    odin.telegram.sender = pkgs.writeShellApplication {
      name = "telegram-send";
      runtimeInputs = [
        pkgs.curl # HTTP(S) client for the Telegram Bot API
        pkgs.coreutils # date, seq, sleep for the retry loop and timestamps
      ];
      text = ''
        set -euo pipefail

        TOKEN="$(cat ${botToken})"
        CHAT_ID="$(cat ${chatId})"
        export TOKEN CHAT_ID

        msg="$1"
        detail="''${2:-}"
        attempts="''${3:-12}"
        if [ -n "$detail" ]; then
          msg="$msg: $detail"
        fi
        # Callers that already format their own time (e.g. the morning digest)
        # set TELEGRAM_SEND_PLAIN=1 to suppress the appended timestamp.
        if [ -z "''${TELEGRAM_SEND_PLAIN:-}" ]; then
          msg="$msg ($(date '+%Y-%m-%d %H:%M %Z'))"
        fi

        for _ in $(seq 1 "$attempts"); do
          if curl -sf -o /dev/null \
            --proxy socks5h://127.0.0.1:10808 \
            --data-urlencode "chat_id=$CHAT_ID" \
            --data-urlencode "text=$msg" \
            "https://api.telegram.org/bot$TOKEN/sendMessage"; then
            exit 0
          fi
          sleep 5
        done
        echo "telegram-send: could not deliver message after $attempts attempts" >&2
        exit 1
      '';
    };
  };
}
