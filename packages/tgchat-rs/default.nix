##
# Package: tgchat-rs
# Purpose: Telegram chat access for the agent and the user as a Rust CLI, on a
#   grammers MTProto user session. Replaces the Python/Telethon `tgchat` once a
#   fresh login has proved the session works: a Telethon session file cannot be
#   read by another library, so the first run is `tgchat-rs login` (phone code,
#   plus the 2FA password when the account has one).
#
# Commands mirror tgchat: login, whoami, dialogs, tail, search, export, send.
# Credentials come from gopass (`api/telegram-telethon-id` / `-hash`), the
# session lives in ~/.local/state/telegram-chat/session.sqlite, and Telegram is
# reached through the sing-box socks5 proxy by default (`features.net`), because
# the MTProto endpoints are unreachable from this host without it.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "tgchat-rs";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Telegram chat access (grammers user session) for the agent and the user";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "tgchat-rs";
  };
}
