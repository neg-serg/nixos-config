{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nemu;
  defaultPackage = pkgs.nemu; # Ncurses UI for QEMU
in
{
  options.programs.nemu = {
    enable = lib.mkEnableOption "nemu (ncurses QEMU frontend)";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = "pkgs._nemu";
      description = "Which nemu package to use.";
    };

    vhostNetGroup = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "vhost";
      description = "Group owning /dev/vhost-net (created with matching udev rule).";
    };

    macvtapGroup = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "vhost";
      description = "Group owning /dev/tapN (macvtap) (created with matching udev rule).";
    };

    usbGroup = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "usb";
      description = "Group owning USB devices (created with matching udev rule).";
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            autoStartDaemon = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Start nemu daemon for the user at boot.";
            };

            autoAddVeth = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Create veth interfaces for the user at boot.";
            };

            autoStartVMs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [
                "vm1"
                "vm2"
              ];
              description = "VMs to start/stop automatically for the user.";
            };
          };
        }
      );
      default = { };
      example = {
        alice = {
          autoAddVeth = true;
          autoStartDaemon = true;
          autoStartVMs = [ "vm1" ];
        };
      };
      description = "Per-user nemu automation settings.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      # ncurses QEMU TUI
    ];

    security.wrappers.nemu = {
      owner = "root";
      group = "root";
      source = "${cfg.package}/bin/nemu";
      capabilities = "cap_net_admin+ep";
    };

    users.groups =
      lib.optionalAttrs (lib.isString cfg.vhostNetGroup) {
        "${cfg.vhostNetGroup}" = { };
      }
      // lib.optionalAttrs (lib.isString cfg.macvtapGroup) {
        "${cfg.macvtapGroup}" = { };
      }
      // lib.optionalAttrs (lib.isString cfg.usbGroup) {
        "${cfg.usbGroup}" = { };
      };

    users.users = lib.mapAttrs' (
      user: _:
      lib.nameValuePair user {
        extraGroups = [
          "kvm"
        ]
        ++ lib.optional (lib.isString cfg.vhostNetGroup) cfg.vhostNetGroup
        ++ lib.optional (lib.isString cfg.macvtapGroup) cfg.macvtapGroup
        ++ lib.optional (lib.isString cfg.usbGroup) cfg.usbGroup;
      }
    ) cfg.users;

    services.udev.extraRules =
      lib.optionalString (lib.isString cfg.vhostNetGroup) ''
        KERNEL=="vhost-net", MODE="0660", GROUP="${cfg.vhostNetGroup}"
      ''
      + lib.optionalString (lib.isString cfg.macvtapGroup) ''
        SUBSYSTEM=="macvtap", MODE="0660", GROUP="${cfg.macvtapGroup}"
      ''
      + lib.optionalString (lib.isString cfg.usbGroup) ''
        SUBSYSTEM=="usb", MODE="0664", GROUP="${cfg.usbGroup}"
      '';

    systemd.targets.nemu = {
      description = "nemu autostart target";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.targets.nemu-veth = {
      description = "nemu veth creation target";
      before = [ "network-pre.target" ];
      wantedBy = [ "nemu.target" ];
    };

    systemd.targets.nemu-vm = {
      description = "nemu autostart target";
      wantedBy = [ "nemu.target" ];
    };

    systemd.services =
      lib.mapAttrs' (
        user: _:
        lib.nameValuePair "nemu-veth-${user}" {
          description = "Create veth interfaces for nemu VMs for ${user}";
          serviceConfig = {
            Type = "oneshot";
            User = user;
            ExecStart = "${config.security.wrapperDir}/nemu -c";
          };
          wantedBy = [ "nemu-veth.target" ];
        }
      ) (lib.filterAttrs (_: userOpts: userOpts.autoAddVeth) cfg.users)
      // lib.mapAttrs' (
        user: _:
        lib.nameValuePair "nemu-uid-${user}" {
          description = "Get UID for ${user} for nemu daemon";
          serviceConfig = {
            Type = "oneshot";
            User = user;
            ExecStart = ''
              /bin/sh -c \
              "${pkgs.coreutils}/bin/echo DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus > /tmp/nemu-daemon-${user}.env" # GNU Core Utilities
            '';
          };
          wantedBy = [ "nemu.target" ];
        }
      ) (lib.filterAttrs (_: userOpts: userOpts.autoAddVeth) cfg.users)
      // lib.mapAttrs' (
        user: _:
        lib.nameValuePair "nemu-daemon-${user}" {
          description = "Start nemu daemon for user ${user}";
          serviceConfig = {
            Type = "forking";
            User = user;
            WorkingDirectory = "/home/${user}";
            EnvironmentFile = "/tmp/nemu-daemon-${user}.env";
            ExecStart = "${config.security.wrapperDir}/nemu --daemon";
          };
          after = [ "nemu-uid-${user}.service" ];
          wantedBy = [ "nemu.target" ];
        }
      ) (lib.filterAttrs (_: userOpts: userOpts.autoStartDaemon) cfg.users)
      // lib.mapAttrs' (
        user: userOpts:
        lib.nameValuePair "nemu-vm-${user}" {
          description = "Start nemu VMs for user ${user}";
          serviceConfig = {
            Type = "oneshot";
            User = user;
            WorkingDirectory = "/home/${user}";
            RemainAfterExit = "yes";
            ExecStart =
              "${config.security.wrapperDir}/nemu --start " + lib.concatStringsSep "," userOpts.autoStartVMs;
            ExecStop =
              "${config.security.wrapperDir}/nemu --poweroff " + lib.concatStringsSep "," userOpts.autoStartVMs;
          };
          after = [
            "network-online.target"
            "nemu-veth-${user}.service"
            "nemu-daemon-${user}.service"
          ];
          wantedBy = [ "nemu-vm.target" ];
        }
      ) (lib.filterAttrs (_: userOpts: userOpts.autoStartVMs != [ ]) cfg.users);
  };
}
