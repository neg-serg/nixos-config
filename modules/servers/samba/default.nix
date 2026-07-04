##
# Module: servers/samba
# Purpose: Simple Samba (SMB/CIFS) fileshare with guest access.
# Key options: cfg = config.servicesProfiles.samba.enable
# Dependencies: None. Creates share directory via tmpfiles.
{
  lib,
  config,
  ...
}:
let
  cfg = config.servicesProfiles.samba or { enable = false; };
  host = config.networking.hostName or "nixos";
  sharePath = "/zero/sync/smb";
in
{
  config = lib.mkIf cfg.enable {
    # Ensure the shared directory exists with permissive access for guests
    systemd.tmpfiles.rules = [
      "d ${sharePath} 0777 root root - -"
    ];

    services.samba = {
      enable = true;
      openFirewall = true; # opens 137-139/udp,tcp and 445/tcp
      # New-style configuration via `settings` (replaces deprecated extraConfig)
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "NixOS Samba Server";
          "netbios name" = host;
          "map to guest" = "Never";
          security = "user"; # replaces securityType
          "bind interfaces only" = "yes";
          interfaces = "lo";
        };
        # Share section (ported from legacy Salt config: smb.conf.j2)
        shared = {
          path = sharePath;
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "neg";
          "force user" = "neg";
          "force group" = "neg";
        };
      };
    };

    # Don't start Samba at boot (removes network-online.target dependency from critical path)
    # Start manually with: systemctl start samba-smbd
    systemd.services.samba-smbd.wantedBy = lib.mkForce [ ];
    systemd.services.samba-nmbd.wantedBy = lib.mkForce [ ];
    systemd.services.samba-winbindd.wantedBy = lib.mkForce [ ];
  };
}
