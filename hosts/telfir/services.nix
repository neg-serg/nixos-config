{lib, ...}: {
  # Primary user (single source of truth for name/ids)
  users.main = {
    name = "neg";
    uid = 1000;
    gid = 1000;
    description = "Neg";
  };
  # Roles enabled for this host
  roles = {
    workstation.enable = true;
    homelab.enable = true;
    media.enable = true;
    monitoring.enable = true;
  };
  # Flake preflight checks disabled

  # Host-specific system policy
  system.autoUpgrade.enable = lib.mkForce false;
  nix = {
    gc.automatic = lib.mkForce false;
    optimise.automatic = lib.mkForce false;
    settings.auto-optimise-store = lib.mkForce false;
  };

  # Service profiles toggles for this host
  servicesProfiles = {
    # Local DNS rewrites for LAN names (service enable comes from roles)
    adguardhome.rewrites = [
      {
        domain = "telfir";
        answer = "192.168.2.240";
      }
      {
        domain = "telfir.local";
        answer = "192.168.2.240";
      }
    ];
    # Explicitly override media role to keep Jellyfin off on this host
    jellyfin.enable = false;
  };

  # Disable Netdata on this host (keep other monitoring like sysstat)
  monitoring.netdata.enable = lib.mkForce false;

  # Nextcloud via Caddy on LAN, served as "telfir"
  services = {
    nextcloud = {
      hostName = "telfir";
      caddyProxy.enable = true;
    };
    caddy.email = "serg.zorg@gmail.com";

    # Syncthing host-specific devices and folders
    syncthing = {
      overrideDevices = true;
      overrideFolders = true;
      settings = {
        devices = {
          "telfir" = {id = "EZG57BT-TANWJ2R-QDVLV5X-4DKP7GU-HQENUT7-MA43GUU-AV3IN6P-7KKGZA3";};
          "Pixel 7 Pro" = {id = "OWGOTRT-Q4LV2MR-QLVIFZH-LPWZ4DP-TANYCAM-SXC2W2A-BL4VSHS-KWXLVAB";};
          "DX180" = {id = "NKSYBIH-G5BV2FK-ZHHL27B-MWZT3OJ-DPTF7TH-O6HE5CM-3CARZ5K-6CIUSQI";};
          "OPPO X7 Ultra" = {id = "JHDQEDC-YN67IMD-B7WFZTI-Y4CPKMY-MUPRBYK-OAFOMPC-IJVDVOV-AOBILAX";};
        };
        folders = {
          "music-upload" = {
            path = "/zero/syncthing/music-upload";
            devices = [
              "telfir"
              "Pixel 7 Pro"
              "DX180"
              "OPPO X7 Ultra"
            ];
          };
          "picture-upload" = {
            path = "/zero/syncthing/picture-upload";
            devices = [
              "Pixel 7 Pro"
              "DX180"
            ];
          };
        };
      };
    };
  };

  # Games autoscale defaults for this host
  profiles.games = {
    autoscaleDefault = false;
    targetFps = 240;
    nativeBaseFps = 240;
  };

  # AutoFDO tooling disabled on this host (module kept)
  dev.gcc.autofdo.enable = false;

  # Monitoring (role enables Netdata + sysstat + atop with light config)
  # Netdata UI: http://127.0.0.1:19999
}
