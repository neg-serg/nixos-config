{
  lib,
  pkgs,
  xdg,
  ...
}: let
  hasAliae = pkgs ? aliae;
in
  lib.mkMerge [
    # Enable Aliae when available in current nixpkgs
    (lib.mkIf hasAliae (lib.mkMerge [
      {programs.aliae.enable = true;}
      # Provide a cross-shell alias set via XDG config.
      # Uses optional blocks when tools are present in nixpkgs.
      (
        let
          hasUg = pkgs ? ugrep;
          hasErd = pkgs ? erdtree;
          hasPrettyping = pkgs ? prettyping;
          hasDuf = pkgs ? duf;
          hasDust = pkgs ? dust;
          hasHandlr = pkgs ? handlr;
          hasWget2 = pkgs ? wget2;
          hasPlocate = pkgs ? plocate;
          hasOuch = pkgs ? ouch;
          hasPigz = pkgs ? pigz;
          hasPbzip2 = pkgs ? pbzip2;
          hasHxd = pkgs ? hexyl || pkgs ? hxd;
          hasMpvc = pkgs ? mpvc;
          hasYtDlp = pkgs ? yt-dlp;
          hasKhal = pkgs ? khal;
          content = lib.concatStrings [
            "# Aliae aliases (cross-shell)\n"
            "# Edit and reload your shell to apply changes.\n"
            "aliases:\n"
            "  l:   \"eza --icons=auto --hyperlink\"\n"
            "  ll:  \"eza --icons=auto --hyperlink -l\"\n"
            "  lsd: \"eza --icons=auto --hyperlink -alD --sort=created --color=always\"\n"
            "  cat: \"bat -pp\"\n"
            "  g:   \"git\"\n"
            "  gs:  \"git status -sb\"\n"
            "  mp:  \"mpv\"\n"
            (lib.optionalString hasHandlr "  e:    \"handlr open\"\n")
            (lib.optionalString hasUg (
              "  grep:  \"ug -G\"\n"
              + "  egrep: \"ug -E\"\n"
              + "  epgrep: \"ug -P\"\n"
              + "  fgrep: \"ug -F\"\n"
              + "  xgrep: \"ug -W\"\n"
              + "  zgrep: \"ug -zG\"\n"
              + "  zegrep: \"ug -zE\"\n"
              + "  zfgrep: \"ug -zF\"\n"
              + "  zpgrep: \"ug -zP\"\n"
              + "  zxgrep: \"ug -zW\"\n"
            ))
            (lib.optionalString hasErd "  tree: \"erd\"\n")
            "  dd:   \"dd status=progress\"\n"
            "  ip:   \"ip -c\"\n"
            "  readelf: \"readelf -W\"\n"
            "  objdump: \"objdump -M intel -d\"\n"
            "  strace:  \"strace -yy\"\n"
            (lib.optionalString hasPrettyping "  ping: \"prettyping\"\n")
            (lib.optionalString hasDuf "  df:   \"duf -theme ansi -hide special -hide-mp \$HOME/* /nix/store /var/lib/*\"\n")
            (lib.optionalString hasDust "  sp:   \"dust -r\"\n")
            (lib.optionalString hasKhal "  cal:  \"khal calendar\"\n")
            (lib.optionalString hasHxd "  hexdump: \"hxd\"\n")
            (lib.optionalString hasOuch "  se: \"ouch decompress --threads 0\"\n")
            (lib.optionalString hasPigz "  gzip: \"pigz\"\n")
            (lib.optionalString hasPbzip2 "  bzip2: \"pbzip2\"\n")
            (lib.optionalString hasPlocate "  locate: \"plocate\"\n")
            "  xz:   \"xz --threads=0\"\n"
            "  zstd: \"zstd --threads=0\"\n"
            (lib.optionalString hasMpvc "  mpvc: \"mpvc -S \$XDG_CONFIG_HOME/mpv/socket\"\n")
            (lib.optionalString hasWget2 "  wget: \"wget2 --hsts-file \$XDG_DATA_HOME/wget-hsts\"\n")
            (lib.optionalString hasYtDlp "  yt:   \"yt-dlp --downloader aria2c --embed-metadata --embed-thumbnail --embed-subs --sub-langs=all\"\n")
            "  ctl: \"systemctl\"\n"
            "  stl: \"sudo systemctl\"\n"
            "  utl: \"systemctl --user\"\n"
            "  ut:  \"systemctl --user start\"\n"
            "  un:  \"systemctl --user stop\"\n"
            "  up:  \"sudo systemctl start\"\n"
            "  dn:  \"sudo systemctl stop\"\n"
          ];
        in
          xdg.mkXdgText "aliae/config.yaml" content
      )
    ]))

    # Soft warning if package is missing
    (lib.mkIf (! hasAliae) {
      warnings = [
        "Aliae is not available in the pinned nixpkgs; skip enabling programs.aliae."
      ];
    })
  ]
