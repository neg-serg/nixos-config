{
  lib,
  pkgs,
  xdg,
  ...
}: let
  hasAliae = pkgs ? aliae;
  hasRg = pkgs ? ripgrep;
  hasNmap = pkgs ? nmap;
  hasCurl = pkgs ? curl;
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
          hasBtm = pkgs ? btm;
          hasIotop = pkgs ? iotop;
          hasLsof = pkgs ? lsof;
          hasKmon = pkgs ? kmon;
          hasReflector = pkgs ? reflector;
          hasFd = pkgs ? fd;
          hasMpc = pkgs ? mpc;
          hasNixify = pkgs ? nixify; # Assuming nixify is a package
          hasNixIndexDb = pkgs ? nix-index-database; # Assuming nix-index-database is a package
          hasFlatpak = pkgs ? flatpak;
          hasBottles = pkgs ? bottles;
          hasObs = pkgs ? obs-studio; # Assuming obs-studio is the package name
          hasOnlyoffice = pkgs ? onlyoffice; # Assuming onlyoffice is the package name
          hasZoom = pkgs ? zoom-us; # Assuming zoom-us is the package name
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
            "  cp:  \"cp --reflink=auto\"\n"
            "  mv:  \"mv -i\"\n"
            "  mk:  \"mkdir -p\"\n"
            "  rd:  \"rmdir\"\n"
            "  x:   \"xargs\"\n"
            "  sort: \"sort --parallel 8 -S 16M\"\n"
            "  :q: \"exit\"\n"
            "  s:   \"sudo \"\n"
            "  dig: \"dig +noall +answer\"\n"
            "  rsync: \"rsync -az --compress-choice=zstd --info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS\"\n"
            "  nrb: \"sudo nixos-rebuild\"\n"
            "  j:   \"journalctl\"\n"
            (lib.optionalString hasBtm "  htop: \"btm -b -T --mem_as_value\"\n")
            (lib.optionalString hasIotop "  iotop: \"sudo iotop -oPa\"\n")
            (lib.optionalString hasLsof "  ports: \"sudo lsof -Pni\"\n")
            (lib.optionalString hasKmon "  kmon: \"sudo kmon -u --color 19683a\"\n")
            (lib.optionalString hasFd "  fd: \"fd -H --ignore-vcs\"\n")
            (lib.optionalString hasFd "  fda: \"fd -Hu\"\n")
            (lib.optionalString hasMpc "  love: \"mpc sendmessage mpdas love\"\n")
            (lib.optionalString hasMpc "  unlove: \"mpc sendmessage mpdas unlove\"\n")
            (lib.optionalString hasYtDlp "  yta: \"yt-dlp --downloader aria2c --embed-metadata --embed-thumbnail --embed-subs --sub-langs=all --write-info-json\"\n")
            (lib.optionalString hasNixify "  nixify: \"nix-shell -p nur.repos.kampka.nixify\"\n")
            (lib.optionalString hasNixIndexDb "  nlocate: \"nix run github:nix-community/nix-index-database\"\n")
            (lib.optionalString hasFlatpak "  bottles: \"flatpak run com.usebottles.bottles\"\n")
            (lib.optionalString hasFlatpak "  obs: \"flatpak run com.obsproject.Studio\"\n")
            (lib.optionalString hasFlatpak "  onlyoffice: \"QT_QPA_PLATFORM=xcb flatpak run org.onlyoffice.desktopeditors\"\n")
            (lib.optionalString hasFlatpak "  zoom: \"flatpak run us.zoom.Zoom\"\n")
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
            (lib.optionalString hasNmap "  nmap-vulners: \"nmap -sV --script=vulners/vulners.nse\"\n")
            (lib.optionalString hasNmap "  nmap-vulscan: \"nmap -sV --script=vulscan/vulscan.nse\"\n")
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
            (lib.optionalString hasCurl "  moon: \"curl wttr.in/Moon\"\n")
            (lib.optionalString hasCurl "  we: \"curl 'wttr.in/?T'\"\n")
            (lib.optionalString hasCurl "  wem: \"curl wttr.in/Moscow?lang=ru\"\n")
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
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
