{
  lib,
  pkgs,
  isNushell ? false,
  homeDir ? "/home/neg",
  ...
}:
let
  mkAlias = name: value: "  - name: ${name}\n    value: ${builtins.toJSON value}\n";
  mkAliasIf =
    cond: name: value:
    if cond then mkAlias name value else "";
  mkEnvVar = name: if isNushell then "$env.${name}" else "$${name}";
  mkCmd = name: if isNushell then "^${name}" else name;
  checks = import ./package-checks.nix { inherit pkgs; };
  inherit (checks)
    hasRg
    hasNmap
    hasCurl
    hasJq
    hasUg
    hasErd
    hasDuf
    hasDust
    hasHandlr
    hasWget2
    hasPlocate
    hasOuch
    hasPigz
    hasPbzip2
    hasHxd
    hasMpvc
    hasMpv
    hasRlwrap
    hasYtDlp
    hasKhal
    hasBtm
    hasIotop
    hasLsof
    hasKmon
    hasFd
    hasMpc
    ;

  # Unconditional aliases: name -> value. Rendered in attr-name order by
  # builtins.attrNames, so the section comments are organizational only.
  aliases = {
    # Core eza/ls aliases
    "ls" = "eza --icons=auto --hyperlink";
    "l" = "eza --icons=auto --hyperlink -lbF --git";
    "ll" = "eza --icons=auto --hyperlink -lbGF --git";
    "llm" = "eza --icons=auto --hyperlink -lbGF --git --sort=modified";
    "la" = "eza --icons=auto --hyperlink -lbhHigUmuSa --time-style=long-iso --git --color-scale";
    "lx" = "eza --icons=auto --hyperlink -lbhHigUmuSa@ --time-style=long-iso --git --color-scale";
    "lt" = "eza --icons=auto --hyperlink --tree --level=2";
    "eza" = "${mkCmd "eza"} --icons=auto --hyperlink";
    "lS" = "eza --icons=auto --hyperlink -1"; # One entry per line
    "lcr" = "eza --icons=auto --hyperlink -al --sort=created --color=always";
    "lsd" = "eza --icons=auto --hyperlink -alD --sort=created --color=always";
    # Core tools
    "cat" = "bat -pp";
    "g" = "git";
    "gs" = "git status -sb";
    "qe" = "${mkCmd "qe"}";
    "acp" = "cp";
    "als" = "ls";
    # Git shortcuts
    "add" = "git add";
    "checkout" = "git checkout";
    "commit" = "git commit";
    "ga" = "git add";
    "gaa" = "git add --all";
    "gam" = "git am";
    "gama" = "git am --abort";
    "gamc" = "git am --continue";
    "gams" = "git am --skip";
    "gamscp" = "git am --show-current-patch";
    "gap" = "git apply";
    "gapa" = "git add --patch";
    "gapt" = "git apply --3way";
    "gau" = "git add --update";
    "gav" = "git add --verbose";
    "gb" = "git branch";
    "gbD" = "git branch -D";
    "gba" = "git branch -a";
    "gbd" = "git branch -d";
    "gbl" = "git blame -b -w";
    "gbnm" = "git branch --no-merged";
    "gbr" = "git branch --remote";
    "gbs" = "git bisect";
    "gbsb" = "git bisect bad";
    "gbsg" = "git bisect good";
    "gbsr" = "git bisect reset";
    "gbss" = "git bisect start";
    "gc" = "git commit -v";
    "gc!" = "git commit -v --amend";
    "gca" = "git commit -v -a";
    "gca!" = "git commit -v -a --amend";
    "gcan!" = "git commit -v -a --no-edit --amend";
    "gcans!" = "git commit -v -a -s --no-edit --amend";
    "gcas" = "git commit -a -s";
    "gcb" = "git checkout -b";
    "gcl" = "git clone --recurse-submodules";
    "gclean" = "git clean -id";
    "gcn!" = "git commit -v --no-edit --amend";
    "gco" = "git checkout";
    "gcor" = "git checkout --recurse-submodules";
    "gcount" = "git shortlog -sn";
    "gcp" = "git cherry-pick";
    "gcpa" = "git cherry-pick --abort";
    "gcpc" = "git cherry-pick --continue";
    "gcs" = "git commit -S";
    "gd" = "git diff -w -U0 --word-diff-regex=[^[:space:]]";
    "gdca" = "git diff --cached";
    "gdcw" = "git diff --cached --word-diff";
    "gds" = "git diff --staged";
    "gdup" = "git diff @{upstream}";
    "gdw" = "git diff --word-diff";
    "gf" = "git fetch";
    "gfa" = "git fetch --all --prune";
    "gfg" = "git ls-files | grep";
    "gfo" = "git fetch origin";
    "gignore" = "git update-index --assume-unchanged";
    "gignored" = "git ls-files -v | grep '^[[:lower:]]'";
    "gl" = "git log -n 4 --oneline";
    "gm" = "git merge";
    "gma" = "git merge --abort";
    "gmtl" = "git mergetool --no-prompt";
    "gp" = "git push";
    "gpd" = "git push --dry-run";
    "gpf" = "git push --force-with-lease";
    "gpf!" = "git push --force";
    "gpv" = "git push -v";
    "gr" = "git remote";
    "gra" = "git remote --add";
    "grb" = "git rebase";
    "grba" = "git rebase --abort";
    "grbc" = "git rebase --continue";
    "grbi" = "git rebase -i";
    "grbo" = "git rebase --onto";
    "grbs" = "git rebase --skip";
    "grev" = "git revert";
    "grh" = "git reset";
    "grhh" = "git reset --hard";
    "grm" = "git rm";
    "grmc" = "git rm --cached";
    "grs" = "git restore";
    "grup" = "git remote update";
    "gsh" = "git show";
    "gsi" = "git submodule init";
    "gsta" = "git stash save";
    "gstaa" = "git stash apply";
    "gstall" = "git stash --all";
    "gstc" = "git stash clear";
    "gstd" = "git stash drop";
    "gstl" = "git stash list";
    "gstp" = "git stash pop";
    "gsts" = "git stash show --text";
    "gstu" = "git stash --include-untracked";
    "gsu" = "git submodule update";
    "gsw" = "git switch";
    "gswc" = "git switch -c";
    "gts" = "git tag -s";
    "gu" = "git reset --soft 'HEAD^'";
    "pull" = "git pull";
    "push" = "git push";
    "resolve" = "git mergetool --tool=nwim";
    "stash" = "git stash";
    "status" = "git status";
    # Misc
    "cp" = "${mkCmd "cp"} --reflink=auto";
    "mv" = "${mkCmd "mv"} -i";
    "mk" = "${mkCmd "mkdir"} -p";
    "rd" = "rmdir";
    "x" = "xargs";
    "sort" = "${mkCmd "sort"} --parallel 8 -S 16M";
    ":q" = "exit";
    "s" = "sudo ";
    "dig" = "${if isNushell then "^dig '+noall' '+answer'" else "dig +noall +answer"}";
    "rsync" = "${
      if isNushell then
        "^rsync -az --compress-choice=zstd '--info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS'"
      else
        "rsync -az --compress-choice=zstd --info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS"
    }";
    "nrb" = "sudo nixos-rebuild";
    "nrs" = "nixos-rebuild switch --no-reexec"; # fast rebuild, skip nixos-rebuild self-eval
    "j" = "journalctl";
    "beet-update" = "beet update -F field_that_isnt -M"; # beets rescan without moving files
    "wl-restart" = "systemctl --user restart wl-daemon.service && sleep 0.5 && wl random ~/pic/wl"; # restart wallpaper daemon
    "jl" = "jupyter lab --no-browser";
    "dosbox" = "${mkCmd "dosbox"} -conf ${mkEnvVar "XDG_CONFIG_HOME"}/dosbox/dosbox.conf";
    "gdb" = "${mkCmd "gdb"} -nh -x ${mkEnvVar "XDG_CONFIG_HOME"}/gdb/gdbinit";
    "iostat" = "${mkCmd "iostat"} --compact -p -h -s";
    "mtrr" = "mtr -wzbe";
    "nvidia-settings" = "nvidia-settings --config=${mkEnvVar "XDG_CONFIG_HOME"}/nvidia/settings";
    "matrix" = "unimatrix -l Aang -s 95";
    "svn" = "${mkCmd "svn"} --config-dir ${mkEnvVar "XDG_CONFIG_HOME"}/subversion";
    "scp" = "${mkCmd "scp"} -r";
    "dd" = "${mkCmd "dd"} status=progress";
    "ip" = "${mkCmd "ip"} -c";
    "readelf" = "${mkCmd "readelf"} -W";
    "objdump" = "${mkCmd "objdump"} -M intel -d";
    "strace" = "${mkCmd "strace"} -yy";
    "xz" = "${mkCmd "xz"} --threads=0";
    "zstd" = "${mkCmd "zstd"} --threads=0";
    "ctl" = "systemctl";
    "stl" = "sudo systemctl";
    "utl" = "systemctl --user";
    "ut" = "systemctl --user start";
    "un" = "systemctl --user stop";
    "up" = "sudo systemctl start";
    "dn" = "sudo systemctl stop";
  };

  # Conditional aliases: emitted only when the condition holds (package
  # presence or shell flavour), in listed order.
  conditional = [
    (mkAliasIf (!isNushell) "fc" "fc -liE 100")
    (mkAliasIf (!isNushell) "gcam" "git commit -a -m")
    (mkAliasIf (!isNushell) "gcasm" "git commit -a -s -m")
    (mkAliasIf (!isNushell) "gcmsg" "git commit -m")
    (mkAliasIf (!isNushell) "gcsm" "git commit -s -m")
    (mkAliasIf (!isNushell) "gpr" "git pull --rebase")
    (mkAliasIf (!isNushell) "gup" "git pull --rebase")
    (mkAliasIf (!isNushell) "gupa" "git pull --rebase --autostash")
    (mkAliasIf (!isNushell) "gupav" "git pull --rebase --autostash -v")
    (mkAliasIf (!isNushell) "gupv" "git pull --rebase -v")
    (mkAliasIf (!isNushell) "sudo" "sudo ")
    (mkAliasIf (!isNushell) "ssh" "TERM=xterm-256color ssh")
    (mkAliasIf hasMpv "mpv" "${mkCmd "mpv"}")
    (mkAliasIf hasMpv "mp" "${mkCmd "mpv"}")
    (mkAliasIf hasMpv "mpa" "mpv --mute=yes") # mpv audio-only (--mute=yes, not -mute: works in all mpv versions)
    (mkAliasIf hasMpv "mpi" "mpv --interpolation=yes --tscale=oversample --video-sync=display-resample")
    (mkAliasIf hasRg "rg"
      "${mkCmd "rg"} --max-columns=0 --max-columns-preview --glob '!*.git*' --glob '!*.obsidian' --colors=match:fg:25 --colors=match:style:underline --colors=line:fg:cyan --colors=line:style:bold --colors=path:fg:249 --colors=path:style:bold --smart-case --hidden"
    )
    (mkAliasIf hasNmap "nmap-vulners" "nmap -sV --script=vulners/vulners.nse")
    (mkAliasIf hasNmap "nmap-vulscan" "nmap -sV --script=vulscan/vulscan.nse")
    (mkAliasIf hasDuf "df"
      "duf --theme neg --style plain --no-header --bar-style modern --hide special --hide-mp '${homeDir}/*,/var/lib/*,/nix/store'"
    )
    (mkAliasIf hasDust "sp" "dust -r")
    (mkAliasIf hasKhal "cal" "khal calendar")
    (mkAliasIf hasHxd "hexdump" "hxd")
    (mkAliasIf hasOuch "se" "ouch decompress")
    (mkAliasIf hasOuch "pk" "ouch compress")
    (mkAliasIf hasPigz "gzip" "pigz")
    (mkAliasIf hasPbzip2 "bzip2" "pbzip2")
    (mkAliasIf hasPlocate "locate" "plocate")
    (mkAliasIf hasMpvc "mpvc" "${mkCmd "mpvc"} -S ${mkEnvVar "XDG_CONFIG_HOME"}/mpv/socket")
    (mkAliasIf hasWget2 "wget" "wget2 --hsts-file ${mkEnvVar "XDG_DATA_HOME"}/wget-hsts")
    (mkAliasIf hasYtDlp "yt" "yt-dlp --proxy socks5://127.0.0.1:10808 --cookies-from-browser vivaldi")
    (mkAliasIf hasCurl "moon" "curl wttr.in/Moon")
    (mkAliasIf hasCurl "we" "curl 'wttr.in/?T'")
    (mkAliasIf hasCurl "wem" "curl wttr.in/Moscow?lang=ru")
    (mkAliasIf (hasCurl && hasJq) "cht" "${mkCmd "cht"}")
    (mkAliasIf hasRlwrap "bb" "rlwrap bb")
    (mkAliasIf hasRlwrap "fennel" "rlwrap fennel")
    (mkAliasIf hasRlwrap "guile" "rlwrap guile")
    (mkAliasIf hasRlwrap "irb" "rlwrap irb")
    (mkAliasIf hasBtm "htop" "btm -b -T --mem_as_value")
    (mkAliasIf hasIotop "iotop" "sudo iotop -oPa")
    (mkAliasIf hasLsof "ports" "sudo lsof -Pni")
    (mkAliasIf hasKmon "kmon" "sudo kmon -u --color 19683a")
    (mkAliasIf hasFd "fd" "${mkCmd "fd"} -H --ignore-vcs")
    (mkAliasIf hasFd "fda" "${mkCmd "fd"} -Hu")
    (mkAliasIf hasMpc "love" "mpc sendmessage mpdas love")
    (mkAliasIf hasMpc "unlove" "mpc sendmessage mpdas unlove")
    (mkAliasIf hasHandlr "e" "handlr open")
    (mkAliasIf hasErd "tree" "erd")
    (mkAliasIf hasUg "grep" "ug -G")
    (mkAliasIf hasUg "egrep" "ug -E")
    (mkAliasIf hasUg "epgrep" "ug -P")
    (mkAliasIf hasUg "fgrep" "ug -F")
    (mkAliasIf hasUg "xgrep" "ug -W")
    (mkAliasIf hasUg "zgrep" "ug -zG")
  ];

  content = lib.concatStrings [
    "# Aliae aliases (cross-shell)\n"
    "# Edit and reload your shell to apply changes.\n"
    "alias:\n"
    (lib.concatMapStrings (n: mkAlias n aliases.${n}) (builtins.attrNames aliases))
    (lib.concatStrings conditional)
  ];
in
content
