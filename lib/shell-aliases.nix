# Generate shell aliases as a Nix attrset for use with programs.*.shellAliases
# This avoids IFD by generating aliases at Nix evaluation time
{
  lib,
  pkgs,
  isNushell ? false,
  homeDir ? "/home/neg",
  ...
}:
let
  # Helper for environment variables (Nushell needs $env.VAR)
  mkEnvVar = name: if isNushell then "$env.${name}" else "\$${name}";

  # Helper for recursive aliases/standard commands in Nushell (force external)
  mkCmd = name: if isNushell then "^${name}" else name;

  # Package availability checks
  hasRg = pkgs ? ripgrep;
  hasNmap = pkgs ? nmap;
  hasCurl = pkgs ? curl;
  hasJq = pkgs ? jq;
  hasUg = pkgs ? ugrep;
  hasErd = pkgs ? erdtree;
  hasPrettyping = pkgs ? prettyping;
  hasDuf = pkgs ? neg && pkgs.neg ? duf;
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
  hasKhal = pkgs ? khal;
  hasBtm = pkgs ? btm;
  hasIotop = pkgs ? iotop;
  hasLsof = pkgs ? lsof;
  hasKmon = pkgs ? kmon;
  hasFd = pkgs ? fd;
  hasMpc = pkgs ? mpc;
  hasFlatpak = pkgs ? flatpak;

  # Conditional alias helper
  optionalAlias = cond: attrs: if cond then attrs else { };

  # Base aliases (always included)
  baseAliases = {
    # Core eza/ls aliases
    ls = "eza --icons=auto --hyperlink --group-directories-first";
    l = "eza --icons=auto --hyperlink --group-directories-first -lbF --git";
    ll = "eza --icons=auto --hyperlink --group-directories-first -lbGF --git";
    llm = "eza --icons=auto --hyperlink --group-directories-first -lbGF --git --sort=modified";
    la = "eza --icons=auto --hyperlink --group-directories-first -lbhHigUmuSa --time-style=long-iso --git --color-scale";
    lx = "eza --icons=auto --hyperlink --group-directories-first -lbhHigUmuSa@ --time-style=long-iso --git --color-scale";
    lt = "eza --icons=auto --hyperlink --group-directories-first --tree --level=2";
    eza = "${mkCmd "eza"} --icons=auto --hyperlink --group-directories-first";
    lS = "eza --icons=auto --hyperlink --group-directories-first -1";
    lcr = "eza --icons=auto --hyperlink --group-directories-first -al --sort=created --color=always";
    # lsd = "eza --icons=auto --hyperlink --group-directories-first -alD --sort=created --color=always";

    # Core tools
    cat = "bat -pp";
    g = "git";
    gs = "git status -sb";
    qe = "${mkCmd "qe"}";
    acp = "cp";
    als = "ls";

    # Git shortcuts
    add = "git add";
    checkout = "git checkout";
    commit = "git commit";
    ga = "git add";
    gaa = "git add --all";
    gam = "git am";
    gama = "git am --abort";
    gamc = "git am --continue";
    gams = "git am --skip";
    gamscp = "git am --show-current-patch";
    gap = "git apply";
    gapa = "git add --patch";
    gapt = "git apply --3way";
    gau = "git add --update";
    gav = "git add --verbose";
    gb = "git branch";
    gbD = "git branch -D";
    gba = "git branch -a";
    gbd = "git branch -d";
    gbl = "git blame -b -w";
    gbnm = "git branch --no-merged";
    gbr = "git branch --remote";
    gbs = "git bisect";
    gbsb = "git bisect bad";
    gbsg = "git bisect good";
    gbsr = "git bisect reset";
    gbss = "git bisect start";
    gc = "git commit -v";
    "gc!" = "git commit -v --amend";
    gca = "git commit -v -a";
    "gca!" = "git commit -v -a --amend";
    "gcan!" = "git commit -v -a --no-edit --amend";
    "gcans!" = "git commit -v -a -s --no-edit --amend";
    gcas = "git commit -a -s";
    gcb = "git checkout -b";
    gcl = "git clone --recurse-submodules";
    gclean = "git clean -id";
    "gcn!" = "git commit -v --no-edit --amend";
    gco = "git checkout";
    gcor = "git checkout --recurse-submodules";
    gcount = "git shortlog -sn";
    gcp = "git cherry-pick";
    gcpa = "git cherry-pick --abort";
    gcpc = "git cherry-pick --continue";
    gcs = "git commit -S";
    gd = "git diff -w -U0 --word-diff-regex=[^[:space:]]";
    gdca = "git diff --cached";
    gdcw = "git diff --cached --word-diff";
    gds = "git diff --staged";
    gdup = "git diff @{upstream}";
    gdw = "git diff --word-diff";
    gf = "git fetch";
    gfa = "git fetch --all --prune";
    gfg = "git ls-files | grep";
    gfo = "git fetch origin";
    gignore = "git update-index --assume-unchanged";
    gignored = "git ls-files -v | grep '^[[:lower:]]'";
    gl = "git pull";
    gm = "git merge";
    gma = "git merge --abort";
    gmtl = "git mergetool --no-prompt";
    gp = "git push";
    gpd = "git push --dry-run";
    gpf = "git push --force-with-lease";
    "gpf!" = "git push --force";
    gpv = "git push -v";
    gr = "git remote";
    gra = "git remote --add";
    grb = "git rebase";
    grba = "git rebase --abort";
    grbc = "git rebase --continue";
    grbi = "git rebase -i";
    grbo = "git rebase --onto";
    grbs = "git rebase --skip";
    grev = "git revert";
    grh = "git reset";
    grhh = "git reset --hard";
    grm = "git rm";
    grmc = "git rm --cached";
    grs = "git restore";
    grup = "git remote update";
    gsh = "git show";
    gsi = "git submodule init";
    gsps = "git show --pretty=short --show-signature";
    gsta = "git stash save";
    gstaa = "git stash apply";
    gstall = "git stash --all";
    gstc = "git stash clear";
    gstd = "git stash drop";
    gstl = "git stash list";
    gstp = "git stash pop";
    gsts = "git stash show --text";
    gstu = "git stash --include-untracked";
    gsu = "git submodule update";
    gsw = "git switch";
    gswc = "git switch -c";
    gts = "git tag -s";
    gu = "git reset --soft 'HEAD^'";
    gwch = "git whatchanged -p --abbrev-commit --pretty=medium";
    pull = "git pull";
    push = "git push";
    resolve = "git mergetool --tool=nwim";
    stash = "git stash";
    status = "git status";

    # Containers
    nerdctl = "nix shell nixpkgs#nerdctl -c nerdctl";
    podman = "nix shell nixpkgs#podman -c podman";
    podman-compose = "nix shell nixpkgs#podman-compose -c podman-compose";
    podman-tui = "nix shell nixpkgs#podman-tui -c podman-tui";
    mergiraf = "nix shell nixpkgs#mergiraf -c mergiraf";
    ctop = "nix shell nixpkgs#ctop -c ctop";
    dive = "nix shell nixpkgs#dive -c dive";
    onefetch = "nix shell nixpkgs#onefetch -c onefetch";
    cpufetch = "nix shell nixpkgs#cpufetch -c cpufetch";
    ramfetch = "nix shell nixpkgs#ramfetch -c ramfetch";
    rhash = "nix shell nixpkgs#rhash -c rhash";
    borgbackup = "nix shell nixpkgs#borgbackup -c borgbackup";
    fclones = "nix shell nixpkgs#fclones -c fclones";
    jdupes = "nix shell nixpkgs#jdupes -c jdupes";
    miller = "nix shell nixpkgs#miller -c miller";
    taplo = "nix shell nixpkgs#taplo -c taplo";
    xidel = "nix shell nixpkgs#xidel -c xidel";
    tewi = "nix run github:neg-serg/tewi";
    bt-migrate = "nix shell nixpkgs#bt-migrate -c bt-migrate";

    playscii = "nix run github:neg-serg/playscii --";
    richcolors = "nix run github:neg-serg/richcolors --";
    bitmagnet = "nix shell nixpkgs#bitmagnet -c bitmagnet";
    jackett = "nix shell nixpkgs#jackett -c jackett";
    sad = "nix shell nixpkgs#sad -c sad";
    grex = "nix shell nixpkgs#grex -c grex";
    enca = "nix shell nixpkgs#enca -c enca";
    choose = "nix shell nixpkgs#choose -c choose";
    sd = "nix shell nixpkgs#sd -c sd";
    streamlink = "nix shell nixpkgs#streamlink -c streamlink";
    lucida = "nix shell nixpkgs#lucida-downloader -c lucida";
    netsniff-ng = "nix shell nixpkgs#netsniff-ng";
    wl-ocr = "nix run github:neg-serg/wl-ocr --";
    tws = "nix run github:neg-serg/tws --";
    music-clap = "nix run github:neg-serg/music-clap";
    webcamize = "nix run github:neg-serg/webcamize --";
    subsonic-tui = "nix run github:neg-serg/subsonic-tui --";
    neopyter = "nix run github:neg-serg/neopyter --";
    blissify-rs = "nix run github:neg-serg/blissify-rs --";
    ls-iommu = "nix run github:neg-serg/ls-iommu --";
    rtcqs = "nix run github:neg-serg/rtcqs --";

    # Misc
    # Run


    # System
    transmission-exporter = "nix run github:neg-serg/transmission-exporter";
    mkvcleaner = "nix run github:neg-serg/mkvcleaner";
    cxxmatrix = "nix run github:neg-serg/cxxmatrix";
    cp = "${mkCmd "cp"} --reflink=auto";
    mv = "${mkCmd "mv"} -i";
    mk = "${mkCmd "mkdir"} -p";
    rd = "rmdir";
    x = "xargs";
    sort = "${mkCmd "sort"} --parallel 8 -S 16M";
    ":q" = "exit";
    s = "sudo ";
    dig = if isNushell then "^dig '+noall' '+answer'" else "dig +noall +answer";
    rsync =
      if isNushell then
        "^rsync -az --compress-choice=zstd '--info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS'"
      else
        "rsync -az --compress-choice=zstd --info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS";
    nrb = "sudo nixos-rebuild";
    j = "journalctl";
    emptydir = "${mkCmd "emptydir"}";
    jl = "jupyter lab --no-browser";
    dosbox = "${mkCmd "dosbox"} -conf ${mkEnvVar "XDG_CONFIG_HOME"}/dosbox/dosbox.conf";
    gdb = "${mkCmd "gdb"} -nh -x ${mkEnvVar "XDG_CONFIG_HOME"}/gdb/gdbinit";
    iostat = "${mkCmd "iostat"} --compact -p -h -s";
    mtrr = "mtr -wzbe";
    nvidia-settings = "nvidia-settings --config=${mkEnvVar "XDG_CONFIG_HOME"}/nvidia/settings";
    matrix = "unimatrix -l Aang -s 95";
    svn = "${mkCmd "svn"} --config-dir ${mkEnvVar "XDG_CONFIG_HOME"}/subversion";
    scp = "${mkCmd "scp"} -r";
    dd = "${mkCmd "dd"} status=progress";
    ip = "${mkCmd "ip"} -c";
    readelf = "${mkCmd "readelf"} -W";
    objdump = "${mkCmd "objdump"} -M intel -d";
    strace = "${mkCmd "strace"} -yy";
    xz = "${mkCmd "xz"} --threads=0";
    zstd = "${mkCmd "zstd"} --threads=0";
    ctl = "systemctl";
    stl = "sudo systemctl";
    utl = "systemctl --user";
    ut = "systemctl --user start";
    un = "systemctl --user stop";
    up = "sudo systemctl start";
    dn = "sudo systemctl stop";
  };

  # Conditional aliases
  conditionalAliases = lib.mergeAttrsList [
    (optionalAlias hasMpv {
      mpv = "${mkCmd "mpv"}";
      mp = "${mkCmd "mpv"}";
      mpa = "${mkCmd "mpa"}";
      mpi = "${mkCmd "mpi"}";
    })
    (optionalAlias hasRg {
      rg = "${mkCmd "rg"} --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden";
    })
    (optionalAlias hasNmap {
      nmap-vulners = "nmap -sV --script=vulners/vulners.nse";
      nmap-vulscan = "nmap -sV --script=vulscan/vulscan.nse";
    })
    (optionalAlias hasPrettyping { ping = "prettyping"; })
    (optionalAlias hasDuf {
      df = "duf --theme neg --style plain --no-header --bar-style modern --hide special --hide-mp '${homeDir}/*,/var/lib/*,/nix/store'";
    })
    (optionalAlias hasDust { sp = "dust -r"; })
    (optionalAlias hasKhal { cal = "khal calendar"; })
    (optionalAlias hasHxd { hexdump = "hxd"; })
    (optionalAlias hasOuch {
      se = "ouch decompress";
      pk = "ouch compress";
    })
    (optionalAlias hasPigz { gzip = "pigz"; })
    (optionalAlias hasPbzip2 { bzip2 = "pbzip2"; })
    (optionalAlias hasPlocate { locate = "plocate"; })
    (optionalAlias hasMpvc {
      mpvc = "${mkCmd "mpvc"} -S ${mkEnvVar "XDG_CONFIG_HOME"}/mpv/socket";
    })
    (optionalAlias hasWget2 {
      wget = "wget2 --hsts-file ${mkEnvVar "XDG_DATA_HOME"}/wget-hsts";
    })
    (optionalAlias hasCurl {
      moon = "curl wttr.in/Moon";
      we = "curl 'wttr.in/?T'";
      wem = "curl wttr.in/Moscow?lang=ru";
    })
    (optionalAlias (hasCurl && hasJq) { cht = "${mkCmd "cht"}"; })
    (optionalAlias hasRlwrap {
      bb = "rlwrap bb";
      fennel = "rlwrap fennel";
      guile = "rlwrap guile";
      irb = "rlwrap irb";
    })
    (optionalAlias hasBtm { htop = "btm -b -T --mem_as_value"; })
    (optionalAlias hasIotop { iotop = "sudo iotop -oPa"; })
    (optionalAlias hasLsof { ports = "sudo lsof -Pni"; })
    (optionalAlias hasKmon { kmon = "sudo kmon -u --color 19683a"; })
    (optionalAlias hasFd {
      fd = "${mkCmd "fd"} -H --ignore-vcs";
      fda = "${mkCmd "fd"} -Hu";
    })
    (optionalAlias hasMpc {
      love = "mpc sendmessage mpdas love";
      unlove = "mpc sendmessage mpdas unlove";
    })
    (optionalAlias hasHandlr { e = "handlr open"; })
    (optionalAlias hasErd { tree = "erd"; })
    (optionalAlias hasFlatpak {
      bottles = "flatpak run com.usebottles.bottles";
      obs = "flatpak run com.obsproject.Studio";
      zoom = "flatpak run us.zoom.Zoom";
    })
    (optionalAlias hasUg {
      grep = "ug -G";
      egrep = "ug -E";
      epgrep = "ug -P";
      fgrep = "ug -F";
      xgrep = "ug -W";
      zgrep = "ug -zG";
      zegrep = "ug -zE";
      zfgrep = "ug -zF";
      zpgrep = "ug -zP";
      zxgrep = "ug -zW";
    })
    (optionalAlias (!isNushell) {
      sudo = "sudo ";
      ssh = "TERM=xterm-256color ssh";
      fc = "fc -liE 100";
      gcam = "git commit -a -m";
      gcasm = "git commit -a -s -m";
      gcmsg = "git commit -m";
      gcsm = "git commit -s -m";
      gpr = "git pull --rebase";
      gup = "git pull --rebase";
      gupa = "git pull --rebase --autostash";
      gupav = "git pull --rebase --autostash -v";
      gupv = "git pull --rebase -v";
      onlyoffice = "QT_QPA_PLATFORM=xcb flatpak run org.onlyoffice.desktopeditors";
    })
  ];
in
baseAliases // conditionalAliases
