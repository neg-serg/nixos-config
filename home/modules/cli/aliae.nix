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
  hasJq = pkgs ? jq;
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
          hasMpv = pkgs ? mpv;
          hasRlwrap = pkgs ? rlwrap;
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
            "alias:\n"
            "  l:   \"eza --icons=auto --hyperlink\"\n"
            "  ll:  \"eza --icons=auto --hyperlink -l\"\n"
            "  lsd: \"eza --icons=auto --hyperlink -alD --sort=created --color=always\"\n"
            "  ls:  eza --icons=auto --hyperlink\n"
            "  cat: \"bat -pp\"\n"
            "  g:   \"git\"\n"
            "  gs:  \"git status -sb\"\n"
            "  qe:  qe\n"
            "  acp: \"cp\"\n"
            "  als: \"ls\"\n"
            "  lcr: \"eza --icons=auto --hyperlink -al --sort=created --color=always\"\n"
            "  add: git add\n"
            "  checkout: git checkout\n"
            "  commit: git commit\n"
            "  eza: eza --icons=auto --hyperlink\n"
            "  fc: fc -liE 100\n"
            "  ga: git add\n"
            "  gaa: git add --all\n"
            "  gam: git am\n"
            "  gama: git am --abort\n"
            "  gamc: git am --continue\n"
            "  gams: git am --skip\n"
            "  gamscp: git am --show-current-patch\n"
            "  gap: git apply\n"
            "  gapa: git add --patch\n"
            "  gapt: git apply --3way\n"
            "  gau: git add --update\n"
            "  gav: git add --verbose\n"
            "  gb: git branch\n"
            "  gbD: git branch -D\n"
            "  gba: git branch -a\n"
            "  gbd: git branch -d\n"
            "  gbl: git blame -b -w\n"
            "  gbnm: git branch --no-merged\n"
            "  gbr: git branch --remote\n"
            "  gbs: git bisect\n"
            "  gbsb: git bisect bad\n"
            "  gbsg: git bisect good\n"
            "  gbsr: git bisect reset\n"
            "  gbss: git bisect start\n"
            "  gc: git commit -v\n"
            "  gc!: git commit -v --amend\n"
            "  gca: git commit -v -a\n"
            "  gca!: git commit -v -a --amend\n"
            "  gcam: git commit -a -m\n"
            "  gcan!: git commit -v -a --no-edit --amend\n"
            "  gcans!: git commit -v -a -s --no-edit --amend\n"
            "  gcas: git commit -a -s\n"
            "  gcasm: git commit -a -s -m\n"
            "  gcb: git checkout -b\n"
            "  gcl: git clone --recurse-submodules\n"
            "  gclean: git clean -id\n"
            "  gcmsg: git commit -m\n"
            "  gcn!: git commit -v --no-edit --amend\n"
            "  gco: git checkout\n"
            "  gcor: git checkout --recurse-submodules\n"
            "  gcount: git shortlog -sn\n"
            "  gcp: git cherry-pick\n"
            "  gcpa: git cherry-pick --abort\n"
            "  gcpc: git cherry-pick --continue\n"
            "  gcs: git commit -S\n"
            "  gcsm: git commit -s -m\n"
            "  gd: git diff -w -U0 --word-diff-regex=[^[:space:]]\n"
            "  gdca: git diff --cached\n"
            "  gdcw: git diff --cached --word-diff\n"
            "  gds: git diff --staged\n"
            "  gdup: git diff @{upstream}\n"
            "  gdw: git diff --word-diff\n"
            "  gf: git fetch\n"
            "  gfa: git fetch --all --prune\n"
            "  gfg: git ls-files | grep\n"
            "  gfo: git fetch origin\n"
            "  gignore: git update-index --assume-unchanged\n"
            "  gignored: git ls-files -v | grep '^[[:lower:]]'\n"
            "  gl: git pull\n"
            "  gm: git merge\n"
            "  gma: git merge --abort\n"
            "  gmtl: git mergetool --no-prompt\n"
            "  gp: git push\n"
            "  gpd: git push --dry-run\n"
            "  gpf: git push --force-with-lease\n"
            "  gpf!: git push --force\n"
            "  gpr: git pull --rebase\n"
            "  gpristine: git reset --hard && git clean -dffx\n"
            "  gpv: git push -v\n"
            "  gr: git remote\n"
            "  gra: git remote --add\n"
            "  grb: git rebase\n"
            "  grba: git rebase --abort\n"
            "  grbc: git rebase --continue\n"
            "  grbi: git rebase -i\n"
            "  grbo: git rebase --onto\n"
            "  grbs: git rebase --skip\n"
            "  grev: git revert\n"
            "  grh: git reset\n"
            "  grhh: git reset --hard\n"
            "  grm: git rm\n"
            "  grmc: git rm --cached\n"
            "  grs: git restore\n"
            "  grup: git remote update\n"
            "  gsh: git show\n"
            "  gsi: git submodule init\n"
            "  gsps: git show --pretty=short --show-signature\n"
            "  gsta: git stash save\n"
            "  gstaa: git stash apply\n"
            "  gstall: git stash --all\n"
            "  gstc: git stash clear\n"
            "  gstd: git stash drop\n"
            "  gstl: git stash list\n"
            "  gstp: git stash pop\n"
            "  gsts: git stash show --text\n"
            "  gstu: git stash --include-untracked\n"
            "  gsu: git submodule update\n"
            "  gsw: git switch\n"
            "  gswc: git switch -c\n"
            "  gts: git tag -s\n"
            "  gu: git reset --soft 'HEAD^'\n"
            "  gup: git pull --rebase\n"
            "  gupa: git pull --rebase --autostash\n"
            "  gupav: git pull --rebase --autostash -v\n"
            "  gupv: git pull --rebase -v\n"
            "  gwch: git whatchanged -p --abbrev-commit --pretty=medium\n"
            (lib.optionalString hasMpv "  mpv: mpv\n")
            (lib.optionalString hasMpv "  mpa: \"mpa\"\n")
            (lib.optionalString hasMpv "  mpi: \"mpi\"\n")
            "  pull: git pull\n"
            "  push: git push\n"
            "  resolve: git mergetool --tool=nwim\n"
            "  stash: git stash\n"
            "  status: git status\n"
            "  sudo: sudo \n"
            (lib.optionalString hasMpv "  mp:  \"mpv\"\n")
            "  cp:  \"cp --reflink=auto\"\n"
            "  mv:  \"mv -i\"\n"
            "  mk:  \"mkdir -p\"\n"
            "  rd:  \"rmdir\"\n"
            "  x:   \"xargs\"\n"
            "  sort: \"sort --parallel 8 -S 16M\"\n"
            "  :q: \"exit\"\n"
            "  s:   \"sudo \"\n"
            "  dig: \"dig +noall +answer\"\n"
            (lib.optionalString hasRg "  rg: \"rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden\"\n")
            "  rsync: \"rsync -az --compress-choice=zstd --info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS\"\n"
            "  nrb: \"sudo nixos-rebuild\"\n"
            "  j:   \"journalctl\"\n"
            "  emptydir: emptydir\n"
            "  dosbox: dosbox -conf $XDG_CONFIG_HOME/dosbox/dosbox.conf\n"
            "  gdb: gdb -nh -x $XDG_CONFIG_HOME/gdb/gdbinit\n"
            "  iostat: iostat --compact -p -h -s\n"
            "  mtrr: mtr -wzbe\n"
            "  nvidia-settings: nvidia-settings --config=$XDG_CONFIG_HOME/nvidia/settings\n"
            "  ssh: TERM=xterm-256color ssh\n"
            "  matrix: unimatrix -l Aang -s 95\n"
            "  svn: svn --config-dir $XDG_CONFIG_HOME/subversion\n"
            (lib.optionalString hasBtm "  htop: \"btm -b -T --mem_as_value\"\n")
            (lib.optionalString hasIotop "  iotop: \"sudo iotop -oPa\"\n")
            (lib.optionalString hasLsof "  ports: \"sudo lsof -Pni\"\n")
            (lib.optionalString hasKmon "  kmon: \"sudo kmon -u --color 19683a\"\n")
            (lib.optionalString hasFd "  fd: \"fd -H --ignore-vcs\"\n")
            (lib.optionalString hasFd "  fda: \"fd -Hu\"\n")
            (lib.optionalString hasMpc "  love: \"mpc sendmessage mpdas love\"\n")
            (lib.optionalString hasMpc "  unlove: \"mpc sendmessage mpdas unlove\"\n")
            (lib.optionalString hasYtDlp "  yta: \"yt-dlp --downloader aria2c --embed-metadata --embed-thumbnail --embed-subs --sub-langs=all --write-info-json\"\n")
            "  scp: \"scp -r\"\n"
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
            (lib.optionalString hasOuch "  se: \"ouch decompress\"\n")
            (lib.optionalString hasOuch "  pk: \"ouch compress\"\n")
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
            (lib.optionalString (hasCurl && hasJq) "  cht: \"cht\"\n")
            (lib.optionalString hasRlwrap "  bb: \"rlwrap bb\"\n")
            (lib.optionalString hasRlwrap "  fennel: \"rlwrap fennel\"\n")
            (lib.optionalString hasRlwrap "  guile: \"rlwrap guile\"\n")
            (lib.optionalString hasRlwrap "  irb: \"rlwrap irb\"\n")
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
