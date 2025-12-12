{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  cfg = config.features.gui.enable or false;
in {
  imports = [
    # Import the wrapper-manager generic module
    (inputs.wrapper-manager + "/modules/many-wrappers.nix")
  ];

  config = lib.mkIf cfg {
    # Define wrappers using the generic module options
    wrappers = {
      # Nextcloud wrapper with GPU disabled
      nextcloud = {
        basePackage = pkgs.nextcloud-client;
        prependFlags = [
          "--disable-gpu"
          "--disable-software-rasterizer"
        ];
        env = {
          QTWEBENGINE_DISABLE_GPU.value = "1";
          QTWEBENGINE_CHROMIUM_FLAGS.value = "--disable-gpu --disable-software-rasterizer";
        };
      };

      # Pyprland Client wrapper
      pypr-client = {
        basePackage = pkgs.pyprland;
      };

      # Nushell wrapper
      nushell = let
        # Generate the aliae configuration file at build time
        aliaeConfig = pkgs.writeText "aliae.yaml" ''
          # Aliae aliases (cross-shell)
          alias:
            # Core eza/ls aliases
            - name: ls
              value: "eza --icons=auto --hyperlink"
            - name: l
              value: "eza --icons=auto --hyperlink -lbF --git"
            - name: ll
              value: "eza --icons=auto --hyperlink -lbGF --git"
            - name: llm
              value: "eza --icons=auto --hyperlink -lbGF --git --sort=modified"
            - name: la
              value: "eza --icons=auto --hyperlink -lbhHigUmuSa --time-style=long-iso --git --color-scale"
            - name: lx
              value: "eza --icons=auto --hyperlink -lbhHigUmuSa@ --time-style=long-iso --git --color-scale"
            - name: lt
              value: "eza --icons=auto --hyperlink --tree --level=2"
            - name: eza
              value: "eza --icons=auto --hyperlink"
            - name: lS
              value: "eza --icons=auto --hyperlink -1" # One entry per line
            - name: lcr
              value: "eza --icons=auto --hyperlink -al --sort=created --color=always"
            - name: lsd
              value: "eza --icons=auto --hyperlink -alD --sort=created --color=always"
            # Core tools
            - name: cat
              value: "bat -pp"
            - name: g
              value: "git"
            - name: gs
              value: "git status -sb"
            - name: acp
              value: "cp"
            - name: als
              value: "ls"
            # Git shortcuts
            - name: add
              value: "git add"
            - name: checkout
              value: "git checkout"
            - name: commit
              value: "git commit"
            - name: fc
              value: "fc -liE 100"
            - name: ga
              value: "git add"
            - name: gaa
              value: "git add --all"
            - name: gam
              value: "git am"
            - name: gama
              value: "git am --abort"
            - name: gamc
              value: "git am --continue"
            - name: gams
              value: "git am --skip"
            - name: gap
              value: "git apply"
            - name: gapa
              value: "git add --patch"
            - name: gau
              value: "git add --update"
            - name: gav
              value: "git add --verbose"
            - name: gb
              value: "git branch"
            - name: gbD
              value: "git branch -D"
            - name: gba
              value: "git branch -a"
            - name: gbd
              value: "git branch -d"
            - name: gc
              value: "git commit -v"
            - name: gc!
              value: "git commit -v --amend"
            - name: gca
              value: "git commit -v -a"
            - name: gca!
              value: "git commit -v -a --amend"
            - name: gcam
              value: "git commit -a -m"
            - name: gcan!
              value: "git commit -v -a --no-edit --amend"
            - name: gcans!
              value: "git commit -v -a -s --no-edit --amend"
            - name: gcas
              value: "git commit -a -s"
            - name: gcasm
              value: "git commit -a -s -m"
            - name: gcb
              value: "git checkout -b"
            - name: gcl
              value: "git clone --recurse-submodules"
            - name: gclean
              value: "git clean -id"
            - name: gcmsg
              value: "git commit -m"
            - name: gcn!
              value: "git commit -v --no-edit --amend"
            - name: gco
              value: "git checkout"
            - name: gcount
              value: "git shortlog -sn"
            - name: gcp
              value: "git cherry-pick"
            - name: gcpa
              value: "git cherry-pick --abort"
            - name: gcpc
              value: "git cherry-pick --continue"
            - name: gd
              value: "git diff -w -U0 --word-diff-regex=[^[:space:]]"
            - name: gdca
              value: "git diff --cached"
            - name: gds
              value: "git diff --staged"
            - name: gdw
              value: "git diff --word-diff"
            - name: gf
              value: "git fetch"
            - name: gfa
              value: "git fetch --all --prune"
            - name: gfo
              value: "git fetch origin"
            - name: gl
              value: "git pull"
            - name: gm
              value: "git merge"
            - name: gma
              value: "git merge --abort"
            - name: gp
              value: "git push"
            - name: gpd
              value: "git push --dry-run"
            - name: gpf
              value: "git push --force-with-lease"
            - name: gpf!
              value: "git push --force"
            - name: gpr
              value: "git pull --rebase"
            - name: gpristine
              value: "git reset --hard && git clean -dffx"
            - name: gpv
              value: "git push -v"
            - name: gr
              value: "git remote"
            - name: gra
              value: "git remote --add"
            - name: grb
              value: "git rebase"
            - name: grba
              value: "git rebase --abort"
            - name: grbc
              value: "git rebase --continue"
            - name: grbi
              value: "git rebase -i"
            - name: grev
              value: "git revert"
            - name: grh
              value: "git reset"
            - name: grhh
              value: "git reset --hard"
            - name: grm
              value: "git rm"
            - name: grmc
              value: "git rm --cached"
            - name: grs
              value: "git restore"
            - name: grup
              value: "git remote update"
            - name: gsh
              value: "git show"
            - name: gsi
              value: "git submodule init"
            - name: gsta
              value: "git stash save"
            - name: gstaa
              value: "git stash apply"
            - name: gstc
              value: "git stash clear"
            - name: gstd"
              value: "git stash drop"
            - name: gstl
              value: "git stash list"
            - name: gstp"
              value: "git stash pop"
            - name: gsu
              value: "git submodule update"
            - name: gsw
              value: "git switch"
            - name: gswc
              value: "git switch -c"
            # Misc
            - name: sudo
              value: "sudo "
            - name: cp
              value: "cp --reflink=auto"
            - name: mv
              value: "mv -i"
            - name: mk
              value: "mkdir -p"
            - name: rd
              value: "rmdir"
            - name: x
              value: "xargs"
            - name: sort
              value: "sort --parallel 8 -S 16M"
            - name: :q
              value: "exit"
            - name: s
              value: "sudo "
            - name: dig
              value: "dig +noall +answer"
            - name: rsync
              value: "rsync -az --compress-choice=zstd --info=FLIST,COPY,DEL,REMOVE,SKIP,SYMSAFE,MISC,NAME,PROGRESS,STATS"
            - name: nrb
              value: "sudo nixos-rebuild"
            - name: j
              value: "journalctl"
            - name: jl
              value: "jupyter lab --no-browser"
            - name: ip
              value: "ip -c"
            - name: ctl
              value: "systemctl"
            - name: stl
              value: "sudo systemctl"
            - name: utl
              value: "systemctl --user"
            - name: ut
              value: "systemctl --user start"
            - name: un
              value: "systemctl --user stop"
            - name: up
              value: "sudo systemctl start"
            - name: dn
              value: "sudo systemctl stop"
        '';

        # Create a self-contained configuration directory in the Nix store
        # referencing the files from the repo.
        nuConfig = pkgs.runCommand "nushell-config" {} ''
          mkdir -p $out
          cp -r ${../../home/modules/cli/nushell-conf}/* $out/
          chmod -R +w $out

          # Generate static aliae init script
          ${pkgs.aliae}/bin/aliae init nu --config ${aliaeConfig} --print > $out/aliae.nu

          # Patch config.nu to point to the store path files
          sed -i 's|\$"(\$env.XDG_CONFIG_HOME)/nushell|"'"$out"'|g' $out/config.nu
        '';
      in {
        basePackage = pkgs.nushell;
        prependFlags = [
          "--config"
          "${nuConfig}/config.nu"
          "--env-config"
          "${nuConfig}/env.nu"
        ];
        env = {
          # Provide Nushell module search path via NU_LIB_DIRS
          NU_LIB_DIRS.value = "$HOME/.config/nushell/modules";
        };
      };
    };

    # Install the built wrappers into system packages
    environment.systemPackages = [
      config.build.toplevel
      pkgs.oh-my-posh # Required for nushell prompt
    ];
  };
}
