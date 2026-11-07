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
  # Extra shares (e.g. a read-only model directory published to one LAN host).
  # They ride on the same smbd instance, so the global section must listen on
  # every interface those shares are reachable through.
  extraShares = cfg.extraShares or { };
  interfaces = cfg.interfaces or [ "lo" ];
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
          # "Bad User": unknown names fall back to the guest account, which is
          # what a read-only `guest ok = yes` share needs. Authenticated shares
          # are unaffected -- `valid users` still has to name a real account.
          "map to guest" = "Bad User";
          security = "user"; # replaces securityType
          "bind interfaces only" = "yes";
          interfaces = lib.concatStringsSep " " interfaces;
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
      }
      // extraShares;
    };

    # Don't start Samba at boot (removes network-online.target dependency from critical path)
    # Start manually with: systemctl start samba-smbd
    systemd.services.samba-smbd.wantedBy = lib.mkForce [ ];
    systemd.services.samba-nmbd.wantedBy = lib.mkForce [ ];
    systemd.services.samba-winbindd.wantedBy = lib.mkForce [ ];
    systemd.services.samba-smbd.serviceConfig = {
      # Hardening. "strict" is not usable here: smbd writes logs to
      # /var/log/samba and locks to /var/lock/samba, which "strict" remounts
      # read-only ("Read-only file system" at startup). "full" keeps /nix/store,
      # /usr/ /boot and /etc read-only and leaves /var writable.
      ProtectSystem = "full";
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
    systemd.services.samba-nmbd.serviceConfig = {
      # Hardening. "strict" is not usable here: smbd writes logs to
      # /var/log/samba and locks to /var/lock/samba, which "strict" remounts
      # read-only ("Read-only file system" at startup). "full" keeps /nix/store,
      # /usr/ /boot and /etc read-only and leaves /var writable.
      ProtectSystem = "full";
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
    systemd.services.samba-winbindd.serviceConfig = {
      # Hardening. "strict" is not usable here: smbd writes logs to
      # /var/log/samba and locks to /var/lock/samba, which "strict" remounts
      # read-only ("Read-only file system" at startup). "full" keeps /nix/store,
      # /usr/ /boot and /etc read-only and leaves /var writable.
      ProtectSystem = "full";
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
