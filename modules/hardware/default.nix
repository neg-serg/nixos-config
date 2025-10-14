{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.hardware.storage.autoMount;
  here = ./.;
  entries = builtins.readDir here;
  importables =
    lib.mapAttrsToList (
      name: type: let
        path = here + "/${name}";
      in
        if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
        then path
        else if type == "directory" && builtins.pathExists (path + "/default.nix")
        then path
        else null
    )
    entries;
  valveIndexModule = {lib, pkgs, config, ...}: let
    vrCfg = config.hardware.vr.valveIndex;
    monadoRuntime = "${pkgs.monado}/share/openxr/1/openxr_monado.json";
  in {
    options.hardware.vr.valveIndex.enable =
      lib.mkEnableOption "Enable the Valve Index VR stack (Monado/OpenXR, SteamVR helpers, udev rules).";

    config = lib.mkIf vrCfg.enable {
      assertions = [
        {
          assertion = config.hardware.graphics.enable or false;
          message = "Valve Index VR requires hardware.graphics.enable = true.";
        }
      ];

      hardware.steam-hardware.enable = lib.mkDefault true;

      # Provide udev rules for XR devices (Monado + generic XR rules)
      services.udev.packages = lib.mkAfter [pkgs.xr-hardware pkgs.monado];

      environment = {
        systemPackages = lib.mkAfter (with pkgs; [
          monado
          opencomposite
          openvr
          openxr-loader
          steam
          steamcmd
          vulkan-tools
          vulkan-validation-layers
          wlx-overlay-s
        ]);

        sessionVariables = {
          XR_RUNTIME_JSON = monadoRuntime;
          OPENXR_RUNTIME = monadoRuntime;
        };

        etc."openxr/1/active_runtime.json".source = monadoRuntime;
        etc."xdg/openxr/1/active_runtime.json".source = monadoRuntime;
      };

      systemd.user = {
        services.monado = {
          description = "Monado OpenXR runtime service";
          partOf = ["graphical-session.target"];
          wantedBy = ["default.target"];
          after = ["graphical-session-pre.target"];
          serviceConfig = {
            ExecStart = "${pkgs.monado}/bin/monado-service";
            Environment = [
              "XRT_COMPOSITOR_LOG=info"
              "XRT_PRINT_OPTIONS=on"
              "IPC_EXIT_ON_DISCONNECT=OFF"
            ];
            Restart = "on-failure";
            RestartSec = 2;
          };
        };

        sockets.monado = {
          description = "Monado OpenXR runtime socket";
          wantedBy = ["sockets.target"];
          socketConfig = {
            ListenStream = "%t/monado_comp_ipc";
            RemoveOnStop = true;
            FlushPending = true;
          };
        };
      };
    };
  };
  imports = lib.filter (p: p != null) importables ++ [valveIndexModule];
in {
  inherit imports;
  options.hardware.storage.autoMount.enable = lib.mkOption {
    type = lib.types.nullOr lib.types.bool;
    default = null;
    description = "Force enable/disable devmon (removable-media auto-mount). Null keeps module default (enabled).";
    example = true;
  };

  config = {
    services = {
      udisks2.enable = true;
      upower.enable = true;
      # Default to enabled, but allow per-host override via hardware.storage.autoMount.enable
      devmon.enable =
        if (cfg.enable or null) == null
        then lib.mkDefault true
        else cfg.enable;
      fwupd.enable = true;
    };

    hardware = {
      i2c.enable = true;
      bluetooth = {
        enable = true; # disable bluetooth
        powerOnBoot = false;
        settings = {General.Enable = "Source,Sink,Media,Socket";};
      };
      cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      enableAllFirmware = true; # Enable all the firmware
      usb-modeswitch.enable = true; # mode switching tool for controlling 'multi-mode' USB devices.
      enableRedistributableFirmware = true;
    };

    # Packages moved to ./pkgs.nix

    powerManagement.cpuFreqGovernor = "performance";
  };
}
