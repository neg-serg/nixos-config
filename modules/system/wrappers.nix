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
        aliaeContent = import ../../lib/aliae.nix {
          inherit lib pkgs;
          isNushell = true;
        };
        aliaeConfig = pkgs.writeText "aliae.yaml" aliaeContent;

        # Create a self-contained configuration directory in the Nix store
        # referencing the files from the repo.
        ohMyPoshInit =
          pkgs.runCommand "oh-my-posh-init.nu" {
            buildInputs = [pkgs.nushell];
          } ''
            export HOME=$TMPDIR
            ${pkgs.oh-my-posh}/bin/oh-my-posh init nu --print > $out
          '';

        nuConfig = pkgs.runCommand "nushell-config" {} ''
          mkdir -p $out
          cp -r ${../../home/modules/cli/nushell-conf}/* $out/
          chmod -R +w $out

          # Generate static aliae init script
          ${pkgs.aliae}/bin/aliae init nu --config ${aliaeConfig} --print > $out/aliae.nu

          # Patch config.nu to point to the store path files
          sed -i 's|\$"(\$env.XDG_CONFIG_HOME)/nushell|"'"$out"'|g' $out/config.nu

          # Substitute placeholders in config.nu
          substituteInPlace $out/config.nu \
            --replace "@OH_MY_POSH_INIT@" "${ohMyPoshInit}"
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
