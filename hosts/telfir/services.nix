{
  lib,
  config,
  pkgs,
  ...
}: {
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

  # Reduce microphone background noise system-wide (PipeWire RNNoise filter)
  # Enabled via modules/hardware/audio/noise by default for this host
  # (If you prefer toggling via an option, we can expose one later.)

  # Hyprland only (no display manager / no Plasma sessions)
  # Plasma session module removed; keep host-level hard disables below.
  # Hard-disable Plasma/X11 stack at the host level to avoid accidental pulls
  # Flake preflight checks disabled

  # Host-specific system policy
  system.autoUpgrade.enable = false;
  nix = {
    gc.automatic = false;
    optimise.automatic = false;
    settings.auto-optimise-store = false;
  };

  # Remove experimental mpv OpenVR overlay

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
    # Enable curated AdGuardHome filter lists
    adguardhome.filterLists = [
      # Core/general
      { name = "AdGuard DNS filter"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"; enabled = true; }
      { name = "OISD full"; url = "https://big.oisd.nl/"; enabled = true; }
      { name = "AdAway"; url = "https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt"; enabled = false; }

      # Well-known hostlists (mostly covered by OISD, kept optional)
      { name = "Peter Lowe's Blocklist"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_3.txt"; enabled = false; }
      { name = "Dan Pollock's Hosts"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_4.txt"; enabled = false; }
      { name = "Steven Black's List"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_33.txt"; enabled = false; }

      # Security-focused
      { name = "Dandelion Sprout Anti‑Malware"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_12.txt"; enabled = true; }
      { name = "Phishing Army"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_18.txt"; enabled = true; }
      { name = "URLHaus Malicious URL"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"; enabled = true; }
      { name = "Scam Blocklist (DurableNapkin)"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_10.txt"; enabled = true; }

      # Niche/optional
      { name = "NoCoin (Cryptomining)"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_8.txt"; enabled = false; }
      { name = "Smart‑TV Blocklist"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_7.txt"; enabled = false; }
      { name = "Game Console Adblock"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_6.txt"; enabled = false; }
      { name = "1Hosts Lite"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt"; enabled = false; }
      { name = "1Hosts Xtra"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_70.txt"; enabled = false; }
    ];
    # Explicitly override media role to keep Jellyfin off on this host
    jellyfin.enable = false;
    # Disable Samba profile on this host
    samba.enable = false;
    # Run a Bitcoin Core node with data stored under /zero/bitcoin-node
    bitcoind = {
      enable = true;
      dataDir = "/zero/bitcoin-node";
    };
  };

  # Disable Netdata on this host (keep other monitoring like sysstat)
  monitoring.netdata.enable = false;

  # Disable RNNoise virtual mic for this host by default
  hardware.audio.rnnoise.enable = false;

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
    # Keep Plasma/X11 off for this host
    desktopManager.plasma6.enable = lib.mkForce false;
    xserver.enable = lib.mkForce false;
    # Remove SDDM/Plasma additions; keep Hyprland-only setup
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
    # Bitcoind instance is now managed by modules/servers/bitcoind
  };

  # Firewall port for bitcoind is opened by the bitcoind server module

  # Disable AppArmor PAM integration for sudo since the kernel lacks AppArmor hats
  security.pam.services = {
    sudo.enableAppArmor = lib.mkForce false;
    "sudo-rs".enableAppArmor = lib.mkForce false;
  };

  # Avoid forcing pkexec as setuid; Steam/SteamVR misbehaves when invoked with elevated EUID.
  # Use polkit rules if specific privileges are required instead of global setuid pkexec.

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
