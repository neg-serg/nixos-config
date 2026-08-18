##
# Module: servers/openssh
# Purpose: OpenSSH + mosh profile (hardened SSH settings).
# Key options: cfg = config.servicesProfiles.openssh.enable
# Dependencies: Enables programs.mosh.
# Hardening: Based on nix-mineral ssh-hardening, compliant with ssh-audit.
{
  lib,
  config,
  ...
}:
let
  cfg = config.servicesProfiles.openssh;
in
{
  options.servicesProfiles.openssh = {
    allowTcpForwarding = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow TCP forwarding. Default false for security.";
    };

    permitTunnel = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow tunnel forwarding. Default false for security.";
    };
  };

  config = lib.mkIf cfg.enable {

    # nixpkgs 26.05: user assertions require explicit isSystemUser + group
    # (mkForce: override nixpkgs service module defaults which lack these)
    users.users.sshd = lib.mkForce {
      isSystemUser = true;
      group = "sshd";
    };
    users.groups.sshd = lib.mkForce { };
    services.openssh = {
      enable = true;
      extraConfig = ''
        # TCP/tunnel forwarding (configurable)
        AllowTcpForwarding ${if cfg.allowTcpForwarding then "yes" else "no"}
        PermitTunnel ${if cfg.permitTunnel then "yes" else "no"}
        # Restrict host key algorithms to modern secure ones
        HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,rsa-sha2-256,rsa-sha2-512,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com
      '';
      settings = {
        # Authentication
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        UseDns = true;

        # PidFile must live under /run/sshd (see RuntimeDirectory below):
        # ProtectSystem=strict makes /run itself read-only, so the default
        # /run/sshd.pid cannot be written ("Read-only file system" in logs).
        PidFile = "/run/sshd/sshd.pid";

        # Hardening (ported from legacy Salt config: sshd-hardening.conf)
        X11Forwarding = false;
        MaxAuthTries = 3;
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;
        LoginGraceTime = 30;
        MaxSessions = 5;

        # Modern ciphers only (AES-GCM preferred)
        Ciphers = [
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
          "aes256-ctr"
          "aes192-ctr"
          "aes128-ctr"
        ];

        # Modern key exchange algorithms
        KexAlgorithms = [
          "sntrup761x25519-sha512@openssh.com"
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
          "diffie-hellman-group18-sha512"
          "diffie-hellman-group16-sha512"
        ];

        # Modern MACs (Encrypt-then-MAC preferred)
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
          "umac-128-etm@openssh.com"
          "hmac-sha2-512"
        ];
      };
    };
    programs.mosh.enable = true; # Opens the relevant UDP ports.
    systemd.services.sshd.serviceConfig = {
      # Hardening
      ProtectSystem = "strict";
      PrivateTmp = true;
      NoNewPrivileges = true;
      # Writable dir for PidFile (exempt from ProtectSystem=strict)
      RuntimeDirectory = "sshd";
    };
  };
}
