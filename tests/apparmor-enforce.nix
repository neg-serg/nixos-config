# Standalone NixOS VM test for modules/security/apparmor.nix.
#
# Run (on-demand, not wired into flake checks — it boots a VM):
#   nix build --impure --file tests/apparmor-enforce.nix
#   nix build --impure --file tests/apparmor-enforce.nix -L   # live log
#
# Documented in docs/howto/apparmor.md. All four profiles run in "enforce"
# here (the repo ships them in "complain"), so a profile that is too tight
# fails this test instead of failing on the host.
let
  flake = builtins.getFlake (toString ../.);
  nixpkgs = flake.inputs.nixpkgs;
  pkgs = nixpkgs.legacyPackages.x86_64-linux;

  # Same option names/defaults as modules/features/security.nix.
  featureDecl = { lib, ... }: {
    options.features.security.apparmor = {
      enable = lib.mkEnableOption "apparmor test";
      sshd = lib.mkOption {
        type = lib.types.enum [
          "disable"
          "complain"
          "enforce"
        ];
        default = "enforce";
      };
      unbound = lib.mkOption {
        type = lib.types.enum [
          "disable"
          "complain"
          "enforce"
        ];
        default = "enforce";
      };
      adguardhome = lib.mkOption {
        type = lib.types.enum [
          "disable"
          "complain"
          "enforce"
        ];
        default = "enforce";
      };
      ntfy = lib.mkOption {
        type = lib.types.enum [
          "disable"
          "complain"
          "enforce"
        ];
        default = "enforce";
      };
    };
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

    # 1. All four profiles are loaded and enforcing.
    print(machine.succeed("aa-status"))
    for exe in ["/bin/sshd", "/bin/unbound", "/bin/AdGuardHome", "/bin/ntfy"]:
        machine.succeed(f"aa-status --json | {jq} -e '.profiles | keys[] | select(endswith(\"{exe}\"))' >/dev/null")
    machine.succeed(f"aa-status --json | {jq} -e '[.profiles[]] | all(. == \"enforce\")'")

    # 2. The daemons survive enforcement.
    for unit in ["sshd.service", "unbound.service", "adguardhome.service", "ntfy-sh.service"]:
        machine.wait_for_unit(unit)

    # 3. Ports are actually served (confinement must not break bind/accept).
    machine.wait_for_open_port(5353, "127.0.0.1")   # unbound
    machine.wait_for_open_port(3000, "127.0.0.1")   # AdGuard admin UI
    machine.wait_for_open_port(2586, "127.0.0.1")   # ntfy
    machine.succeed("curl -fsS http://127.0.0.1:2586/ >/dev/null")

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
        "journalctl -b --no-pager | grep 'apparmor=\"DENIED\"' | grep -E 'sshd|unbound|AdGuardHome|ntfy' || true"
    )
    assert denials.strip() == "", f"unexpected AppArmor denials:\n{denials}"
  '';
}
