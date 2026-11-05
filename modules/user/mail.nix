{ config, pkgs, ... }:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in
{
  # Core mail CLI clients (himalaya, kyotocabinet) install at the system level
  # so they are available even outside the shell sessions. neomutt is a
  # full-screen reader nobody scripts against, so it is an on-demand launcher:
  # the system generation carries the wrapper, the binary is built and rooted
  # under ~/.local/state/nix-apps on the first run.
  environment.systemPackages = [
    pkgs.himalaya # async email CLI with IMAP/SMTP sync + TUI prompts
    pkgs.kyotocabinet # DB backend for himalaya cache (faster than sqlite)
    (onDemand {
      name = "neomutt";
      attr = "neomutt";
    }) # terminal mail client for full-screen workflows, built on first use
    pkgs.vdirsyncer # Cal/CardDAV sync to keep contacts/calendars local
  ];
}
