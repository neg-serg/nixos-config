{ pkgs, ... }:
{
  # Core mail CLI clients (himalaya, neomutt, kyotocabinet) now install at the
  # system level so they are available even outside the shell sessions.
  environment.systemPackages = [
    pkgs.himalaya # async email CLI with IMAP/SMTP sync + TUI prompts
    pkgs.kyotocabinet # DB backend for himalaya cache (faster than sqlite)
    pkgs.neomutt # terminal mail client for full-screen workflows
    pkgs.vdirsyncer # Cal/CardDAV sync to keep contacts/calendars local
  ];
}
