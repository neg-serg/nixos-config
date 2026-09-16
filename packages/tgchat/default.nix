{
  python3,
  writeShellApplication,
  coreutils, # PATH helpers used by the wrapper
  gopass, # credentials: api/telegram-telethon-{id,hash}
  gnupg, # gpg fallback for the same credentials
  qrencode, # renders the login QR into a PNG the user scans
}:
# Telethon client for the user's Telegram account: read dialogs, tail chats
# and send messages as the user. Session and login state live outside the
# store (~/.local/state/telegram-chat), so a login survives rebuilds.
let
  pythonEnv = python3.withPackages (ps: [
    ps.telethon # MTProto client (user session, not a bot)
    ps.python-socks # socks5 transport for the local sing-box proxy
  ]);
in
writeShellApplication {
  name = "tgchat";
  runtimeInputs = [
    pythonEnv
    coreutils
    gopass
    gnupg
    qrencode
  ];
  text = ''exec python3 ${./tg.py} "$@"'';
  meta = {
    description = "Telegram chat access via Telethon (read/send as the user)";
    maintainers = [ ]; # local-only package, nothing here is upstream
  };
}
