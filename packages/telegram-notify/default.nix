##
# Package: telegram-notify
# Purpose: The Telegram notification binaries for trantor — a morning calendar
#   digest (khal → telegram-send), the 12:00 pill reminder with its "Mark taken"
#   button (Bot API through curl, marker file for at-most-once sending) and the
#   crash-loop scanner that reads NRestarts from both systemd managers.
#   `telegram-pill-bot` also serves as a general assistant: `/status` renders a
#   deterministic monitoring snapshot, and every other text is answered by the
#   local llama-swap model (monitoring is context, not the only allowed topic).
#   The same bot owns the notes surface (`src/notes.rs`): `/note`, `/notes`,
#   `/nb` plus the matching model tools create, read, append, search, tag and
#   delete notes in the user's zk notebook, and run `nb` to pull/commit/push
#   it. Writes drop from the unit's root to the notebook owner through
#   `runuser`, so new notes stay neg-owned.
#   `assets/avatar.svg` is the bot's profile picture: a pure-vector phosphor CRT
#   (labels are outlined from a bitmap font, so no font or image dependency),
#   with the 512/1024 raster exports that BotFather's `/setuserpic` needs.
#
# Rust, no crates. The sender/curl invocation stays external on purpose: the
# repo already ships `telegram-send` with the socks-proxy retry policy, and the
# Bot API is only reachable through that proxy. Paths and the retry policy come
# from the unit environment, which keeps the binaries free of build-time
# substitution (and makes them testable against stubs).
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "telegram-notify";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Telegram notifications and local-model Q&A for trantor";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "telegram-calendar-reminder";
  };
}
