{
  lib,
  pkgs,
  config,
  ...
}:
let
  hishtoryPkg = pkgs.hishtory or null; # Your shell history: synced, queryable, and in context
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  environment.shellAliases = {
    newsraft = "nix run nixpkgs#newsraft --";
  };

  environment.systemPackages = [
    pkgs.ripgrep # better grep
    # Diff tools
    pkgs.delta # better diff tool
    (onDemand {
      name = "difft";
      attr = "difftastic";
    }) # structural diff that understands syntax; built on first use
    pkgs.diffutils # classic diff utils

    # File management
    pkgs.convmv # convert filename encodings
    pkgs.dos2unix # file conversion
    pkgs.elio # terminal file manager: places/files/preview panes, inline images, archive and trash handling
    pkgs.fd # better find
    pkgs.file # detect file type by content
    pkgs.massren # massive rename utility
    pkgs.stow # manage farms of symlinks
    pkgs.zoxide # smarter cd with ranking

    # Utilities
    pkgs.dcfldd # dd with progress/hash
    pkgs.dust # better du
    pkgs.eza # modern 'ls' replacement
    pkgs.lazytail # TUI log viewer: live filtering, follow mode, multi-tab; also runs as an MCP server (lazytail --mcp)
    pkgs.libnotify # notify-send helper used by CLI scripts
    pkgs.moreutils # assorted unix utils (sponge, etc.)
    pkgs.neg.duf # better df (fork with plain style support)
    pkgs.neg.termeverything # Wayland compositor that renders GUI windows in the terminal
    pkgs.neg.lusty # native file/buffer picker for Neovim (Lusty successor)
    (onDemand {
      name = "tgchat";
      attr = "tgchat";
    }) # Telegram chat access for the agent (Telethon, user session), built on first use
    (onDemand {
      name = "tgchat-rs";
      attr = "tgchat-rs";
    }) # Telegram chat access on a grammers session — replaces tgchat after the first `tgchat-rs login`
    pkgs.neg.tint # Colouriser for CLI output — token scanners + per-tool rulesets, wired into zsh
    pkgs.procs # modern 'ps' replacement
    pkgs.pwgen # password generator
    pkgs.sd # intuitive find & replace CLI (sed replacement)
    pkgs.wlrctl # command-line utility for miscellaneous wlroots Wayland extensions
    # Wallpaper / cartography
    pkgs.neg.topowall # topographic contour wallpapers from real elevation data (GPU render)
    (onDemand {
      name = "terrascope";
      attr = "terrascope";
    }) # interactive world map in the terminal (braille; live weather/aircraft/earthquakes)

    # Python
    (pkgs.python3.withPackages (ps: [ ps.pexpect ])) # python3 with pexpect for expect-style automation
  ]
  ++ lib.optional (hishtoryPkg != null) hishtoryPkg # sync shell history w/ encryption, better than zsh-histdb
  # uutils wins the PATH name collisions: its default meta.priority (5) beats
  # coreutils-full's (10), and GNU stays in the closure. Only PATH-level lookups
  # change — absolute store paths (activation, units, shebangs) keep GNU. Measured:
  # `sort` ~2x and `ls -R` ~1.9x slower, `cp`/`base64` faster.
  ++ lib.optional (config.lib.neg.enabled "cli.uutils") pkgs.uutils-coreutils-noprefix;
}
