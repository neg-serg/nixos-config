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

      # ncpamixer wrapper (audio mixer)
      ncpamixer = let
        ncpaConfig = pkgs.writeText "ncpamixer.conf" (builtins.readFile ../../home/modules/media/audio/ncpamixer.conf);
      in {
        basePackage = pkgs.ncpamixer;
        prependFlags = [
          "-c"
          "${ncpaConfig}"
        ];
      };

      # Nushell wrapper
      nushell = let
        # Generate the aliae configuration file at build time
        aliaeContent = import ../../lib/aliae.nix {
          inherit lib pkgs;
          isNushell = true;
        };
        aliaeConfig = pkgs.writeText "aliae.yaml" aliaeContent;

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

                    # Substitute placeholders in config.nu with RUNTIME logic
                    # We use a constant string path for source to avoid parse errors.
          substituteInPlace $out/config.nu \
            --replace "source @OH_MY_POSH_INIT@" "
          source ~/.cache/oh-my-posh.nu
          "
        '';

        nushellRun = pkgs.writeShellScriptBin "nu" ''
          mkdir -p ~/.cache/oh-my-posh
          ${pkgs.oh-my-posh}/bin/oh-my-posh init nu --print > ~/.cache/oh-my-posh.nu 2>/dev/null || true
          exec ${pkgs.nushell}/bin/nu "$@"
        '';
      in {
        basePackage = nushellRun;
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

      # Bash wrapper
      bash = let
        # Aliae configuration for Bash
        aliaeContentBash = import ../../lib/aliae.nix {
          inherit lib pkgs;
          isNushell = false;
        };
        aliaeConfigBash = pkgs.writeText "aliae-bash.yaml" aliaeContentBash;

        bashConfig = pkgs.runCommand "bash-config" {} ''
          mkdir -p $out

          # Generate static aliae init script
          ${pkgs.aliae}/bin/aliae init bash --config ${aliaeConfigBash} > $out/aliae.bash

          cat <<EOF > $out/bashrc
          # Source global definitions
          if [ -f /etc/bashrc ]; then
              . /etc/bashrc
          fi

          # Bash options from old config
          shopt -qs autocd 2>/dev/null
          shopt -qs cdspell 2>/dev/null
          shopt -qs checkhash 2>/dev/null
          shopt -s checkwinsize 2>/dev/null
          shopt -s cmdhist 2>/dev/null
          shopt -qs direxpand 2>/dev/null
          shopt -qs dirspell 2>/dev/null
          shopt -qs dotglob 2>/dev/null
          shopt -qs extglob 2>/dev/null
          shopt -qs extquote 2>/dev/null
          shopt -qs globstar 2>/dev/null
          shopt -qs histappend histreedit histverify 2>/dev/null
          shopt -qs hostcomplete 2>/dev/null
          shopt -s nocaseglob nocasematch 2>/dev/null

          # Custom functions
          any(){
              [ -n "\$1" ] && ps uwwwp \$(pgrep -f "\$@")
          }

          # Bindings (skip if not interactive or warnings issues)
          bind 'set show-all-if-ambiguous on' 2>/dev/null || true
          bind 'set completion-ignore-case on' 2>/dev/null || true
          bind 'set completion-map-case on' 2>/dev/null || true
          bind 'TAB:menu-complete' 2>/dev/null || true
          bind 'set mark-symlinked-directories on' 2>/dev/null || true

          # History settings
          HISTFILESIZE=100000
          HISTCONTROL="erasedups:ignoreboth"
          export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"
          HISTTIMEFORMAT='%F %T '

          # Initialize Aliae aliases
          source $out/aliae.bash

           # Initialize Oh-My-Posh (Runtime)
           # mkdir handled in bashRun
           eval "$(${pkgs.oh-my-posh}/bin/oh-my-posh init bash)"

          EOF
        '';

        bashRun = pkgs.writeShellScriptBin "bash" ''
          mkdir -p ~/.cache/oh-my-posh
          echo "DEBUG: PATH=$PATH" > /tmp/posh-debug.log
          echo "DEBUG: HOME=$HOME" >> /tmp/posh-debug.log
          ${pkgs.oh-my-posh}/bin/oh-my-posh init bash --print >> /tmp/posh-debug.log 2>&1
          exec ${pkgs.bashInteractive}/bin/bash --rcfile ${bashConfig}/bashrc "$@"
        '';
      in {
        basePackage = bashRun;
        prependFlags = [];
      };
    };

    # Install the built wrappers into system packages
    environment.systemPackages = [
      config.build.toplevel
      pkgs.oh-my-posh # Required for nushell prompt
    ];
  };
}
