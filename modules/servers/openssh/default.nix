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
    enable = lib.mkEnableOption "OpenSSH server with hardened settings";

    allowTcpForwarding = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow TCP forwarding. Disable for maximum security.";
    };

    permitTunnel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow tunnel forwarding. Disable for maximum security.";
    };
  };

  config = lib.mkIf cfg.enable {
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

        # Hardening: disable X11 forwarding
        X11Forwarding = false;

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
  };
}
