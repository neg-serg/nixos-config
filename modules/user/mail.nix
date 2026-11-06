{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "mail";
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  # Core mail CLI clients install at the system level so they are available
  # even outside the shell sessions — but only when the mail stack is on: the
  # service/config side lives in modules/user/nix-maid/sys/mail.nix behind the
  # same flag, and a host that turns mail off should not keep the clients.
  # neomutt is a full-screen reader nobody scripts against, so it is an
  # on-demand launcher: the system generation carries the wrapper, the binary
  # is built and rooted under ~/.local/state/nix-apps on the first run.
  config = lib.mkIf enabled {
    environment.systemPackages = [
      pkgs.himalaya # async email CLI with IMAP/SMTP sync + TUI prompts
      pkgs.kyotocabinet # DB backend for himalaya cache (faster than sqlite)
      (onDemand {
        name = "neomutt";
        attr = "neomutt";
      }) # terminal mail client for full-screen workflows, built on first use
      pkgs.vdirsyncer # Cal/CardDAV sync to keep contacts/calendars local
    ];
  };
}
