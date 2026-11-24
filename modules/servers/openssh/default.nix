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

    useDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Resolve client addresses in sshd (UseDNS). Keep it on only where the
        host answers PTR queries for its clients: a lookup that hangs holds the
        connection in the pre-auth phase until LoginGraceTime, and that failure
        also trips the per-source penalty, so every LAN login dies there.
      '';
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
      # The brute-force alert scanner (hosts/trantor/services/telegram-units.nix)
      # greps the journal for "Failed password", which sshd only logs at
      # VERBOSE. fail2ban used to set this via mkDefault; it stays explicit now
      # that the package is gone.
      settings.LogLevel = "VERBOSE";
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
        UseDns = cfg.useDns;

        # PidFile lives in the RuntimeDirectory the unit creates (/run/sshd),
        # so the daemon writes nothing into the shared /run directly.
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
    # Brute-force mitigation without a daemon: sshd's built-in
    # PerSourcePenalties (OpenSSH >= 9.8) is on by default. It refuses a
    # source address for authfail/invaliduser/grace-exceeded, accumulates
    # repeated penalties up to max and tracks /32 and /128 separately
    # (defaults: authfail 5s, min 15s, max 10m, so one bad key does not lock
    # a device out). The port-22 rule in hosts/trantor/services/policy.nix is
    # deliberately global (sshd must stay reachable on net0/wlan0, the
    # interfaces used on untrusted networks), so this is the compensating
    # control instead of narrowing that rule. fail2ban was removed on purpose:
    # 325 MiB of closure, mostly Python, for zero bans observed, while
    # key-only auth already rejects the scan traffic. PerSourcePenalties is
    # not a Match-block keyword, so the home LAN cannot be exempted the way
    # fail2ban's ignoreIP did.
    systemd.services.sshd.serviceConfig = {
      # Hardening. NoNewPrivileges is deliberately NOT set here: under
      # no_new_privs the kernel refuses every confined->unconfined transition
      # (`apparmor_bprm_creds_for_exec`: info="no new privs"), which is exactly
      # what sshd's AppArmor profile needs for login sessions
      # (modules/security/apparmor-profiles.nix, the `ux` shell rules), and it
      # also disables setuid helpers such as sudo inside every SSH session.
      # Enforce-mode AppArmor confines the daemon instead.
      #
      # ProtectSystem=strict would be inherited by the login sessions: they
      # would see / and /run read-only, so sudo could not write its timestamp
      # directory, nix could not write /nix/var, and /etc/nixos could not be
      # edited over ssh. "yes" protects /usr, /boot and /efi (a bootkit is the
      # concrete risk here) and leaves the rest writable for the session.
      ProtectSystem = "yes";
      PrivateTmp = true;
      # Directory for the PidFile (the openssh module keeps it under /run/sshd).
      RuntimeDirectory = "sshd";
    };
  };
}
