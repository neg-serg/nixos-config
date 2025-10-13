{lib, config, pkgs, ...}: let
  bitcoindProfile = config.servicesProfiles.bitcoind;
in {
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
  system.autoUpgrade.enable = false;
  nix = {
    gc.automatic = false;
    optimise.automatic = false;
    settings.auto-optimise-store = false;
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
    # Enable Samba profile on this host
    samba.enable = true;
    # Run a Bitcoin Core node with data stored under /zero/bitcoin-node
    bitcoind = {
      enable = true;
      dataDir = "/zero/bitcoin-node";
    };
  };

  # Disable Netdata on this host (keep other monitoring like sysstat)
  monitoring.netdata.enable = false;

  # Nextcloud via Caddy on LAN, served as "telfir"
  services = let
    devicesList = [
      {
        name = "telfir";
        id = "EZG57BT-TANWJ2R-QDVLV5X-4DKP7GU-HQENUT7-MA43GUU-AV3IN6P-7KKGZA3";
      }
      {
        name = "Pixel 7 Pro";
        id = "OWGOTRT-Q4LV2MR-QLVIFZH-LPWZ4DP-TANYCAM-SXC2W2A-BL4VSHS-KWXLVAB";
      }
      {
        name = "DX180";
        id = "NKSYBIH-G5BV2FK-ZHHL27B-MWZT3OJ-DPTF7TH-O6HE5CM-3CARZ5K-6CIUSQI";
      }
      {
        name = "OPPO X7 Ultra";
        id = "JHDQEDC-YN67IMD-B7WFZTI-Y4CPKMY-MUPRBYK-OAFOMPC-IJVDVOV-AOBILAX";
      }
    ];
    devices = builtins.listToAttrs (
      map (d: {
        inherit (d) name;
        value = {inherit (d) id;};
      })
      devicesList
    );
    foldersList = [
      {
        name = "music-upload";
        path = "/zero/syncthing/music-upload";
        devices = ["telfir" "Pixel 7 Pro" "DX180" "OPPO X7 Ultra"];
      }
      {
        name = "picture-upload";
        path = "/zero/syncthing/picture-upload";
        devices = ["Pixel 7 Pro" "DX180"];
      }
    ];
    folders = builtins.listToAttrs (
      map (f: {
        inherit (f) name;
        value = {inherit (f) path devices;};
      })
      foldersList
    );
  in {
    # Temporarily disable Ollama on this host
    ollama.enable = false;
    # Avoid port conflicts: ensure nginx is disabled when using Caddy
    nginx.enable = false;
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
        inherit devices folders;
      };
    };
    # Bitcoin Core node (mainnet) data under /zero/bitcoin-node
    bitcoind =
      if bitcoindProfile.enable
      then {
        main = {
          enable = true;
          dataDir = bitcoindProfile.dataDir;
        };
      }
      else {};
  };

  networking.firewall.allowedTCPPorts =
    lib.mkAfter (lib.optional bitcoindProfile.enable bitcoindProfile.p2pPort);

  # Disable AppArmor PAM integration for sudo since the kernel lacks AppArmor hats
  security.pam.services = {
    sudo.enableAppArmor = lib.mkForce false;
    "sudo-rs".enableAppArmor = lib.mkForce false;
  };

  security.wrappers.pkexec = {
    source = "${pkgs.polkit}/bin/pkexec";
    owner = "root";
    group = "root";
    setuid = true;
  };

  # Provide nginx system user/group so PHP-FPM pool configs referencing
  # nginx for socket ownership won't fail even when nginx service is off.
  users = {
    users.nginx = {
      isSystemUser = true;
      group = "nginx";
    };
    groups.nginx = {};
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
