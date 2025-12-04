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

  # Helper to generate alias entry
  mkAlias = name: value: "  - name: ${name}\n    value: ${builtins.toJSON value}\n";

  # Conditional alias
  mkAliasIf = cond: name: value:
    if cond
    then mkAlias name value
    else "";
in
  lib.mkMerge [
    # Enable Aliae when available in current nixpkgs
    (lib.mkIf hasAliae (lib.mkMerge [
      {programs.aliae.enable = true;}
      # Provide a cross-shell alias set via XDG config.
      (
        let
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
          hasYtDlp = pkgs ? yt-dlp;
          hasKhal = pkgs ? khal;
          hasBtm = pkgs ? btm;
          hasIotop = pkgs ? iotop;
          hasLsof = pkgs ? lsof;
          hasKmon = pkgs ? kmon;
          hasFd = pkgs ? fd;
          hasMpc = pkgs ? mpc;
          hasNixIndexDb = pkgs ? nix-index-database;
          hasFlatpak = pkgs ? flatpak;

          content = lib.concatStrings [
            "# Aliae aliases (cross-shell)\n"
            "# Edit and reload your shell to apply changes.\n"
            "alias:\n"
            # Core eza/ls aliases
            (mkAlias "l" "eza --icons=auto --hyperlink")
            (mkAlias "ll" "eza --icons=auto --hyperlink -l")
            (mkAlias "lsd" "eza --icons=auto --hyperlink -alD --sort=created --color=always")
            (mkAlias "ls" "eza --icons=auto --hyperlink")
            (mkAlias "eza" "eza --icons=auto --hyperlink")
            (mkAlias "lcr" "eza --icons=auto --hyperlink -al --sort=created --color=always")
            # Core tools
            (mkAlias "cat" "bat -pp")
            (mkAlias "g" "git")
            (mkAlias "gs" "git status -sb")
            (mkAlias "qe" "qe")
            (mkAlias "acp" "cp")
            (mkAlias "als" "ls")
            # Git shortcuts
            (mkAlias "add" "git add")
            (mkAlias "checkout" "git checkout")
            (mkAlias "commit" "git commit")
            (mkAlias "fc" "fc -liE 100")
            (mkAlias "ga" "git add")
            (mkAlias "gaa" "git add --all")
            (mkAlias "gam" "git am")
            (mkAlias "gama" "git am --abort")
            (mkAlias "gamc" "git am --continue")
            (mkAlias "gams" "git am --skip")
            (mkAlias "gamscp" "git am --show-current-patch")
            (mkAlias "gap" "git apply")
            (mkAlias "gapa" "git add --patch")
            (mkAlias "gapt" "git apply --3way")
            (mkAlias "gau" "git add --update")
            (mkAlias "gav" "git add --verbose")
            (mkAlias "gb" "git branch")
            (mkAlias "gbD" "git branch -D")
            (mkAlias "gba" "git branch -a")
            (mkAlias "gbd" "git branch -d")
            (mkAlias "gbl" "git blame -b -w")
            (mkAlias "gbnm" "git branch --no-merged")
            (mkAlias "gbr" "git branch --remote")
            (mkAlias "gbs" "git bisect")
            (mkAlias "gbsb" "git bisect bad")
            (mkAlias "gbsg" "git bisect good")
            (mkAlias "gbsr" "git bisect reset")
            (mkAlias "gbss" "git bisect start")
            (mkAlias "gc" "git commit -v")
            (mkAlias "gc!" "git commit -v --amend")
            (mkAlias "gca" "git commit -v -a")
            (mkAlias "gca!" "git commit -v -a --amend")
            (mkAlias "gcam" "git commit -a -m")
            (mkAlias "gcan!" "git commit -v -a --no-edit --amend")
            (mkAlias "gcans!" "git commit -v -a -s --no-edit --amend")
            (mkAlias "gcas" "git commit -a -s")
            (mkAlias "gcasm" "git commit -a -s -m")
            (mkAlias "gcb" "git checkout -b")
            (mkAlias "gcl" "git clone --recurse-submodules")
            (mkAlias "gclean" "git clean -id")
            (mkAlias "gcmsg" "git commit -m")
            (mkAlias "gcn!" "git commit -v --no-edit --amend")
            (mkAlias "gco" "git checkout")
            (mkAlias "gcor" "git checkout --recurse-submodules")
            (mkAlias "gcount" "git shortlog -sn")
            (mkAlias "gcp" "git cherry-pick")
            (mkAlias "gcpa" "git cherry-pick --abort")
            (mkAlias "gcpc" "git cherry-pick --continue")
            (mkAlias "gcs" "git commit -S")
            (mkAlias "gcsm" "git commit -s -m")
            (mkAlias "gd" "git diff -w -U0 --word-diff-regex=[^[:space:]]")
            (mkAlias "gdca" "git diff --cached")
            (mkAlias "gdcw" "git diff --cached --word-diff")
            (mkAlias "gds" "git diff --staged")
            (mkAlias "gdup" "git diff @{upstream}")
            (mkAlias "gdw" "git diff --word-diff")
            (mkAlias "gf" "git fetch")
            (mkAlias "gfa" "git fetch --all --prune")
            (mkAlias "gfg" "git ls-files | grep")
            (mkAlias "gfo" "git fetch origin")
            (mkAlias "gignore" "git update-index --assume-unchanged")
            (mkAlias "gignored" "git ls-files -v | grep '^[[:lower:]]'")
            (mkAlias "gl" "git pull")
            (mkAlias "gm" "git merge")
            (mkAlias "gma" "git merge --abort")
            (mkAlias "gmtl" "git mergetool --no-prompt")
            (mkAlias "gp" "git push")
            (mkAlias "gpd" "git push --dry-run")
            (mkAlias "gpf" "git push --force-with-lease")
            (mkAlias "gpf!" "git push --force")
            (mkAlias "gpr" "git pull --rebase")
            (mkAlias "gpristine" "git reset --hard && git clean -dffx")
            (mkAlias "gpv" "git push -v")
            (mkAlias "gr" "git remote")
            (mkAlias "gra" "git remote --add")
            (mkAlias "grb" "git rebase")
            (mkAlias "grba" "git rebase --abort")
            (mkAlias "grbc" "git rebase --continue")
            (mkAlias "grbi" "git rebase -i")
            (mkAlias "grbo" "git rebase --onto")
            (mkAlias "grbs" "git rebase --skip")
            (mkAlias "grev" "git revert")
            (mkAlias "grh" "git reset")
            (mkAlias "grhh" "git reset --hard")
            (mkAlias "grm" "git rm")
            (mkAlias "grmc" "git rm --cached")
            (mkAlias "grs" "git restore")
            (mkAlias "grup" "git remote update")
            (mkAlias "gsh" "git show")
            (mkAlias "gsi" "git submodule init")
            (mkAlias "gsps" "git show --pretty=short --show-signature")
            (mkAlias "gsta" "git stash save")
            (mkAlias "gstaa" "git stash apply")
            (mkAlias "gstall" "git stash --all")
            (mkAlias "gstc" "git stash clear")
            (mkAlias "gstd" "git stash drop")
            (mkAlias "gstl" "git stash list")
            (mkAlias "gstp" "git stash pop")
            (mkAlias "gsts" "git stash show --text")
            (mkAlias "gstu" "git stash --include-untracked")
            (mkAlias "gsu" "git submodule update")
            (mkAlias "gsw" "git switch")
            (mkAlias "gswc" "git switch -c")
            (mkAlias "gts" "git tag -s")
            (mkAlias "gu" "git reset --soft 'HEAD^'")
            (mkAlias "gup" "git pull --rebase")
            (mkAlias "gupa" "git pull --rebase --autostash")
            (mkAlias "gupav" "git pull --rebase --autostash -v")
            (mkAlias "gupv" "git pull --rebase -v")
            (mkAlias "gwch" "git whatchanged -p --abbrev-commit --pretty=medium")
            (mkAlias "pull" "git pull")
            (mkAlias "push" "git push")
            (mkAlias "resolve" "git mergetool --tool=nwim")
            (mkAlias "stash" "git stash")
            (mkAlias "status" "git status")
            # Misc core aliases
            (mkAlias "sudo" "sudo ")
            (mkAlias "cp" "cp --reflink=auto")
            (mkAlias "mv" "mv -i")
            (mkAlias "mk" "mkdir -p")
            (mkAlias "rd" "rmdir")
            (mkAlias "x" "xargs")
            (mkAlias "sort" "sort --parallel 8 -S 16M")
            (mkAlias ":q" "exit")
            (mkAlias "s" "sudo ")
            (mkAlias "dig" "dig +noall +answer")
            (mkAlias "rsync" "rsync -az --compress-choice=zstd --info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS")
            (mkAlias "nrb" "sudo nixos-rebuild")
            (mkAlias "j" "journalctl")
            (mkAlias "emptydir" "emptydir")
            (mkAlias "dosbox" "dosbox -conf $XDG_CONFIG_HOME/dosbox/dosbox.conf")
            (mkAlias "gdb" "gdb -nh -x $XDG_CONFIG_HOME/gdb/gdbinit")
            (mkAlias "iostat" "iostat --compact -p -h -s")
            (mkAlias "mtrr" "mtr -wzbe")
            (mkAlias "nvidia-settings" "nvidia-settings --config=$XDG_CONFIG_HOME/nvidia/settings")
            (mkAlias "ssh" "TERM=xterm-256color ssh")
            (mkAlias "matrix" "unimatrix -l Aang -s 95")
            (mkAlias "svn" "svn --config-dir $XDG_CONFIG_HOME/subversion")
            (mkAlias "scp" "scp -r")
            (mkAlias "dd" "dd status=progress")
            (mkAlias "ip" "ip -c")
            (mkAlias "readelf" "readelf -W")
            (mkAlias "objdump" "objdump -M intel -d")
            (mkAlias "strace" "strace -yy")
            (mkAlias "xz" "xz --threads=0")
            (mkAlias "zstd" "zstd --threads=0")
            (mkAlias "ctl" "systemctl")
            (mkAlias "stl" "sudo systemctl")
            (mkAlias "utl" "systemctl --user")
            (mkAlias "ut" "systemctl --user start")
            (mkAlias "un" "systemctl --user stop")
            (mkAlias "up" "sudo systemctl start")
            (mkAlias "dn" "sudo systemctl stop")
            # Optional aliases
            (mkAliasIf hasMpv "mpv" "mpv")
            (mkAliasIf hasMpv "mp" "mpv")
            (mkAliasIf hasMpv "mpa" "mpa")
            (mkAliasIf hasMpv "mpi" "mpi")
            (mkAliasIf hasRg "rg" "rg --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden")
            (mkAliasIf hasNmap "nmap-vulners" "nmap -sV --script=vulners/vulners.nse")
            (mkAliasIf hasNmap "nmap-vulscan" "nmap -sV --script=vulscan/vulscan.nse")
            (mkAliasIf hasPrettyping "ping" "prettyping")
            (mkAliasIf hasDuf "df" "duf -theme ansi -hide special -hide-mp '/home/neg/*,/var/lib/*'")
            (mkAliasIf hasDust "sp" "dust -r")
            (mkAliasIf hasKhal "cal" "khal calendar")
            (mkAliasIf hasHxd "hexdump" "hxd")
            (mkAliasIf hasOuch "se" "ouch decompress")
            (mkAliasIf hasOuch "pk" "ouch compress")
            (mkAliasIf hasPigz "gzip" "pigz")
            (mkAliasIf hasPbzip2 "bzip2" "pbzip2")
            (mkAliasIf hasPlocate "locate" "plocate")
            (mkAliasIf hasMpvc "mpvc" "mpvc -S $XDG_CONFIG_HOME/mpv/socket")
            (mkAliasIf hasWget2 "wget" "wget2 --hsts-file $XDG_DATA_HOME/wget-hsts")
            (mkAliasIf hasYtDlp "yt" "yt-dlp --downloader aria2c --embed-metadata --embed-thumbnail --embed-subs --sub-langs=all")
            (mkAliasIf hasYtDlp "yta" "yt-dlp --downloader aria2c --embed-metadata --embed-thumbnail --embed-subs --sub-langs=all --write-info-json")
            (mkAliasIf hasCurl "moon" "curl wttr.in/Moon")
            (mkAliasIf hasCurl "we" "curl 'wttr.in/?T'")
            (mkAliasIf hasCurl "wem" "curl wttr.in/Moscow?lang=ru")
            (mkAliasIf (hasCurl && hasJq) "cht" "cht")
            (mkAliasIf hasRlwrap "bb" "rlwrap bb")
            (mkAliasIf hasRlwrap "fennel" "rlwrap fennel")
            (mkAliasIf hasRlwrap "guile" "rlwrap guile")
            (mkAliasIf hasRlwrap "irb" "rlwrap irb")
            (mkAliasIf hasBtm "htop" "btm -b -T --mem_as_value")
            (mkAliasIf hasIotop "iotop" "sudo iotop -oPa")
            (mkAliasIf hasLsof "ports" "sudo lsof -Pni")
            (mkAliasIf hasKmon "kmon" "sudo kmon -u --color 19683a")
            (mkAliasIf hasFd "fd" "fd -H --ignore-vcs")
            (mkAliasIf hasFd "fda" "fd -Hu")
            (mkAliasIf hasMpc "love" "mpc sendmessage mpdas love")
            (mkAliasIf hasMpc "unlove" "mpc sendmessage mpdas unlove")
            (mkAliasIf hasHandlr "e" "handlr open")
            (mkAliasIf hasErd "tree" "erd")
            (mkAliasIf hasNixIndexDb "nlocate" "nix run github:nix-community/nix-index-database")
            (mkAliasIf hasFlatpak "bottles" "flatpak run com.usebottles.bottles")
            (mkAliasIf hasFlatpak "obs" "flatpak run com.obsproject.Studio")
            (mkAliasIf hasFlatpak "onlyoffice" "QT_QPA_PLATFORM=xcb flatpak run org.onlyoffice.desktopeditors")
            (mkAliasIf hasFlatpak "zoom" "flatpak run us.zoom.Zoom")
            # ugrep aliases
            (mkAliasIf hasUg "grep" "ug -G")
            (mkAliasIf hasUg "egrep" "ug -E")
            (mkAliasIf hasUg "epgrep" "ug -P")
            (mkAliasIf hasUg "fgrep" "ug -F")
            (mkAliasIf hasUg "xgrep" "ug -W")
            (mkAliasIf hasUg "zgrep" "ug -zG")
            (mkAliasIf hasUg "zegrep" "ug -zE")
            (mkAliasIf hasUg "zfgrep" "ug -zF")
            (mkAliasIf hasUg "zpgrep" "ug -zP")
            (mkAliasIf hasUg "zxgrep" "ug -zW")
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
