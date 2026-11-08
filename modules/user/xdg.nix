{
  lib,
  pkgs,
  config,
  neg,
  ...
}:
let
  packages = [
    pkgs.handlr # xdg-open replacement with per-handler rules
    pkgs.xdg-utils # classic xdg helpers (xdg-open/xdg-mime/etc.)
    pkgs.xdg-ninja # detect mislocated files in $HOME
  ];

  termfilechooser = config.features.gui.termfilechooser.enable;

  # Repo data, store-copied: the portal is a system service and must not depend
  # on a writable working tree.
  pickerDir = config.lib.neg.path "files/broot/termfilechooser";

  # The wrapper is a shell script with three store paths spliced in. Keeping it
  # in files/ (instead of a Nix string) keeps it shellcheck-able and free of
  # `''${…}` escaping.
  brootFileChooser = pkgs.writeShellApplication {
    name = "broot-filechooser";
    runtimeInputs = [
      pkgs.broot # the picker itself
      pkgs.coreutils # realpath/rm for the save-placeholder cleanup
      pkgs.kitty # default terminal hosting the picker (TERMCMD overrides it)
    ];
    text =
      lib.replaceStrings
        [ "@pickerDir@" "@broot@" "@kitty@" ]
        [ "${pickerDir}" "${lib.getExe pkgs.broot}" "${lib.getExe pkgs.kitty}" ]
        (builtins.readFile (config.lib.neg.path "files/broot/termfilechooser/wrapper.sh"));
  };

  fileChooserImpl = if termfilechooser then [ "termfilechooser" ] else [ "gtk" ];
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = lib.mkAfter packages;
      xdg.portal = {
        enable = true;
        xdgOpenUsePortal = true;
        extraPortals = [
          # Hyprland portal is provided via programs.hyprland.portalPackage
          pkgs.xdg-desktop-portal-gtk # GTK file picker portal backend (generic, works on any DE/WM)
        ]
        ++ lib.optional termfilechooser pkgs.xdg-desktop-portal-termfilechooser;
        config = {
          common.default = [
            "hyprland"
          ];
          common."org.freedesktop.impl.portal.FileChooser" = fileChooserImpl;
          hyprland.default = [
            "hyprland"
          ];
          hyprland."org.freedesktop.impl.portal.FileChooser" = fileChooserImpl;
        };
      };

      # Ensure Hyprland portal starts reliably by dropping the ConditionEnvironment
      # check from the user unit. Hyprland already imports the necessary env vars
      # into the systemd user manager at session start.
      systemd.user.services.xdg-desktop-portal-hyprland.unitConfig.ConditionEnvironment = lib.mkForce "";
    }

    # xdg-desktop-portal-termfilechooser is built with SYSCONFDIR inside its own
    # store path (meson joins prefix and sysconfdir), so /etc/xdg is never
    # consulted — the portal reads $XDG_CONFIG_HOME/xdg-desktop-portal-termfilechooser
    # before that store path. The picker config therefore has to be a user file.
    # create_help_file=0 keeps SaveFile from pre-creating a help-text file at the
    # suggested path: the wrapper makes an empty placeholder instead and removes
    # it again when the dialog is cancelled.
    (lib.mkIf termfilechooser (
      neg.mkHomeFiles {
        ".config/xdg-desktop-portal-termfilechooser/config".text = ''
          [filechooser]
          cmd=${brootFileChooser}/bin/broot-filechooser
          create_help_file=0
          default_dir=$HOME
          open_mode=suggested
          save_mode=suggested
        '';
      }
    ))
  ];
}
