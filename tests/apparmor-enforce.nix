# Standalone NixOS VM test for modules/security/apparmor.nix.
#
# Run (on-demand, not wired into flake checks — it boots a VM):
#   just apparmor-test
#
# The recipe adds the two flags this file needs and nothing else does: --offline
# (the closure is local; without it nix stalls on the caches' narinfo lookups)
# and --no-link (never clobber the host's ./result).
#
# Documented in docs/howto/apparmor.md. All eight profiles run in "enforce"
# here (the repo ships them in "complain"), so a profile that is too tight
# fails this test instead of failing on the host.
let
  flake = builtins.getFlake (toString ../.);
  nixpkgs = flake.inputs.nixpkgs;
  pkgs = nixpkgs.legacyPackages.x86_64-linux;

  # Config files for the three session daemons. tmpfiles copies them into place
  # (`C`), it does not symlink them: a store symlink is exactly the trap the
  # host's homeFiles/etcFiles fields exist for, and this test is about the
  # daemon's own rules, not about that rebuild machinery.
  singboxConfig = pkgs.writeText "singbox-test-config.json" (
    builtins.toJSON {
      log = {
        level = "error";
        timestamp = false;
      };
      inbounds = [
        {
          type = "socks";
          tag = "socks-in";
          listen = "127.0.0.1";
          listen_port = 1080;
        }
      ];
      outbounds = [
        {
          type = "direct";
          tag = "direct";
        }
      ];
    }
  );

  transmissionSettings = pkgs.writeText "transmission-test-settings.json" (
    builtins.toJSON {
      download-dir = "/home/test/torrent/data";
      incomplete-dir-enabled = false;
      watch-dir-enabled = false;
      rpc-enabled = true;
      rpc-bind-address = "127.0.0.1";
      rpc-port = 9091;
      rpc-authentication-required = false;
      rpc-whitelist-enabled = false;
      peer-port = 51413;
      peer-port-random-on-start = false;
      dht-enabled = false;
      lpd-enabled = false;
      utp-enabled = false;
      port-forwarding-enabled = false;
      blocklist-enabled = false;
    }
  );

  aria2Conf = pkgs.writeText "aria2-test.conf" ''
    dir=/home/test/dw/aria
    enable-rpc=true
    rpc-listen-all=false
    rpc-listen-port=6800
    save-session=/home/test/.local/share/aria2/session
    save-session-interval=1800
    continue=true
  '';

  # Same option names/defaults as modules/features/security.nix.
  featureDecl = { lib, ... }: {
    options.features.security.apparmor = {
      enable = lib.mkEnableOption "apparmor test";
    }
    //
      lib.genAttrs
        [
          "sshd"
          "unbound"
          "adguardhome"
          "ntfy"
          "avahi"
          "singbox"
          "transmission"
          "aria2"
        ]
        (
          name:
          lib.mkOption {
            description = "AppArmor state for the ${name} profile (this test runs everything in enforce).";
            type = lib.types.enum [
              "disable"
              "complain"
              "enforce"
            ];
            default = "enforce";
          }
        );
  };
in
pkgs.testers.nixosTest {
  name = "apparmor-daemons-enforce";
  nodes.machine =
    {
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        ../modules/security/apparmor.nix
        featureDecl
      ];
      features.security.apparmor = {
        enable = true;
        sshd = "enforce";
        unbound = "enforce";
        adguardhome = "enforce";
        ntfy = "enforce";
        avahi = "enforce";
        singbox = "enforce";
        transmission = "enforce";
        aria2 = "enforce";
      };

      security.apparmor = {
        enable = true;
        packages = [ pkgs.apparmor-profiles ];
      };

      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PasswordAuthentication = false;
        };
      };
      services.unbound = {
        enable = true;
        settings.server = {
          interface = [ "127.0.0.1" ];
          port = 5353;
          "do-daemonize" = false;
        };
      };
      services.adguardhome = {
        enable = true;
        settings = {
          dns = {
            bind_hosts = [ "127.0.0.1" ];
            port = 5354;
            upstream_dns = [ "127.0.0.1:5353" ];
          };
        };
      };
      services.ntfy-sh = {
        enable = true;
        settings = {
          base-url = "http://127.0.0.1:2586";
          listen-http = ":2586";
        };
      };
      services.avahi = {
        enable = true;
        nssmdns4 = true;
      };

      # ---- stand-ins for the three session daemons ----------------------------
      # On the host these are user@1000 services (sing-box-proxy,
      # transmission-daemon, aria2), so they run as a normal user here too: a
      # profile attaches to the executable path either way, but running them as
      # root would demand capabilities the host's user never has (aria2 asking
      # for CAP_DAC_READ_SEARCH, for one) and turn the "no denials" assertion
      # into a lie about the host. Their paths mirror the host's `/home/*/...`
      # rules, and the config files are copied into place by tmpfiles (`C`)
      # rather than symlinked, because a store symlink is the trap the host's
      # homeFiles/etcFiles fields exist for — not what this test is about.
      users.users.test = {
        isNormalUser = true;
        home = "/home/test";
      };
      systemd.tmpfiles.rules = [
        "d /home/test/.config 0755 test users -"
        "d /home/test/.config/sing-box-test 0755 test users -"
        "C /home/test/.config/sing-box-test/config.json 0644 test users - ${singboxConfig}"
        "d /home/test/.config/transmission-daemon 0755 test users -"
        "d /home/test/torrent/data 0755 test users -"
        "C /home/test/.config/transmission-daemon/settings.json 0644 test users - ${transmissionSettings}"
        "d /home/test/.config/aria2 0755 test users -"
        "C /home/test/.config/aria2/aria2.conf 0644 test users - ${aria2Conf}"
        "d /home/test/.local/share/aria2 0755 test users -"
        "d /home/test/dw/aria 0755 test users -"
      ];
      systemd.services.singbox-test = {
        description = "sing-box SOCKS proxy (test stand-in for sing-box-proxy.service)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "test";
          Group = "users";
          ExecStart = "${pkgs.sing-box}/bin/sing-box run -c /home/test/.config/sing-box-test/config.json";
          Restart = "no";
        };
      };
      systemd.services.transmission-test = {
        description = "transmission-daemon (test stand-in for transmission-daemon.service)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "test";
          Group = "users";
          ExecStart = "${pkgs.transmission_4}/bin/transmission-daemon -g /home/test/.config/transmission-daemon -f --log-level=error";
          Restart = "no";
        };
      };
      systemd.services.aria2-test = {
        description = "aria2 (test stand-in for aria2.service)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "test";
          Group = "users";
          ExecStart = "${pkgs.aria2}/bin/aria2c --conf-path=/home/test/.config/aria2/aria2.conf";
          Restart = "no";
        };
      };

      # Mirror the host: AdGuard Home runs as a static user, not DynamicUser
      # (nixpkgs' DynamicUser state dir under /var/lib/private is not readable by
      # the pre-start script — see modules/servers/adguardhome/default.nix).
      users.groups.adguardhome = lib.mkForce { };
      users.users.adguardhome = lib.mkForce {
        isSystemUser = true;
        group = "adguardhome";
        home = "/var/lib/AdGuardHome";
        description = "AdGuard Home service account";
      };
      systemd.services.adguardhome.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "adguardhome";
      };

      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;
      system.stateVersion = "26.05";
      documentation.enable = false;
    };

  testScript = ''
    jq = "${pkgs.jq}/bin/jq"

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("apparmor.service")

    # 1. All eight profiles are loaded and enforcing.
    print(machine.succeed("aa-status"))
    for exe in [
        "/bin/sshd",
        "/bin/unbound",
        "/bin/AdGuardHome",
        "/bin/ntfy",
        "/bin/avahi-daemon",
        "/bin/sing-box",
        "/bin/transmission-daemon",
        "/bin/aria2c",
    ]:
        machine.succeed(f"aa-status --json | {jq} -e '.profiles | keys[] | select(endswith(\"{exe}\"))' >/dev/null")
    machine.succeed(f"aa-status --json | {jq} -e '[.profiles[]] | all(. == \"enforce\")'")

    # 2. The daemons survive enforcement.
    for unit in [
        "sshd.service",
        "unbound.service",
        "adguardhome.service",
        "ntfy-sh.service",
        "avahi-daemon.service",
        "singbox-test.service",
        "transmission-test.service",
        "aria2-test.service",
    ]:
        machine.wait_for_unit(unit)

    # 3. Ports are actually served (confinement must not break bind/accept).
    machine.wait_for_open_port(5353, "127.0.0.1")   # unbound
    machine.wait_for_open_port(3000, "127.0.0.1")   # AdGuard admin UI
    machine.wait_for_open_port(2586, "127.0.0.1")   # ntfy
    machine.succeed("curl -fsS http://127.0.0.1:2586/ >/dev/null")
    machine.wait_for_open_port(1080, "127.0.0.1")   # sing-box SOCKS
    machine.wait_for_open_port(9091, "127.0.0.1")   # transmission RPC
    machine.wait_for_open_port(6800, "127.0.0.1")   # aria2 RPC
    machine.succeed("ss -lun | grep -q ':5353 '")   # avahi mDNS

    # 3a. The three session daemons answer, not merely listen: an RPC request
    #     through the SOCKS inbound, the transmission RPC handshake (409 until
    #     the session id is echoed back) and an aria2 JSON-RPC call.
    machine.succeed("curl -fsS --socks5 127.0.0.1:1080 http://127.0.0.1:2586/ >/dev/null")
    machine.succeed(
        "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9091/transmission/rpc | grep -q 409"
    )
    machine.succeed(
        "curl -fsS -d '{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"aria2.getVersion\"}'"
        " http://127.0.0.1:6800/jsonrpc | grep -q '\"version\"'"
    )

    # 3b. Dump the denials seen so far — they are the diff to review when a
    #     profile needs another rule (asserted at the end).
    print(machine.succeed("journalctl -b --no-pager | grep 'apparmor=\"DENIED\"' || true"))

    # 4. sshd keeps working end to end: login + session command.
    machine.succeed("ssh-keygen -t ed25519 -N \"\" -f /root/aa-key -q")
    machine.succeed(
        "mkdir -p /root/.ssh && cat /root/aa-key.pub >> /root/.ssh/authorized_keys"
        " && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"
    )
    machine.succeed(
        "ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i /root/aa-key root@127.0.0.1"
        " 'echo SSH-SESSION-OK' | grep -q SSH-SESSION-OK"
    )

    # 5. No denials from the confined daemons: in enforce mode a missing rule
    #    shows up as a broken service, this catches silent partial breakage.
    denials = machine.succeed(
        "journalctl -b --no-pager | grep 'apparmor=\"DENIED\"'"
        " | grep -E 'sshd|unbound|AdGuardHome|ntfy|avahi-daemon|sing-box|transmission-daemon|aria2c' || true"
    )
    assert denials.strip() == "", f"unexpected AppArmor denials:\n{denials}"
  '';
}
