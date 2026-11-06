##
# Package: telegram-notify
# Purpose: The Telegram notification binaries for trantor — a morning calendar
#   digest (khal → telegram-send), the 12:00 pill reminder with its "Mark taken"
#   button (Bot API through curl, marker file for at-most-once sending) and the
#   crash-loop scanner that reads NRestarts from both systemd managers.
#   `telegram-pill-bot` also serves free-text questions: `/status` renders a
#   deterministic monitoring snapshot and everything else is answered by the
#   local llama-swap model.
#
# Rust, no crates. The sender/curl invocation stays external on purpose: the
# repo already ships `telegram-send` with the socks-proxy retry policy, and the
# Bot API is only reachable through that proxy. Paths and the retry policy come
# from the unit environment, which keeps the binaries free of build-time
# substitution (and makes them testable against stubs).
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "telegram-notify";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Telegram notifications and local-model Q&A for trantor";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "telegram-calendar-reminder";
  };
}
