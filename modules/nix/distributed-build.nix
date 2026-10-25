##
# Module: nix/distributed-build
# Purpose: let builds run on a second x86_64 machine over SSH instead of queueing
# behind trantor's `max-jobs = 1`. That cap is deliberate (settings.nix: two
# 16-core jobs blew the 40G memcg cap), so one heavy build leaves the local
# daemon idle; a cheap remote box fills the gap with unrelated small
# derivations. Declared builders are best-effort: when the host is unreachable
# Nix logs the failure and builds locally, so keeping this enabled cannot break
# a rebuild. `builders-use-substitutes = true` (settings.nix) is what makes the
# split pay off — the builder pulls inputs from its own substituters (it sits in
# the EU and reaches cache.nixos.org directly) instead of receiving them over
# the SSH link.
# Key options: features.nix.remoteBuilder.enable (default true).
# Dependencies: sops.secrets."nix-builder-key" — secrets/nix-builder-key.sops.yaml
# holds the passphrase-less ed25519 key the *daemon* (root, not neg) uses to log
# in. The matching public key must be in the builder's authorized_keys and the
# ssh user must be listed in that host's nix.settings.trusted-users, otherwise
# `nix-daemon --stdio` is refused and every job falls back to local builds.
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.nix.remoteBuilder;

  # Public host key of late.sh, from `ssh-keyscan -t ed25519 late.sh`
  # (SHA256:Tc7aeaaQulKJeF3C/zd2BKvq/KgaQTHyMPNa3s9K+aE); re-check it when the
  # VPS is rebuilt. Goes into programs.ssh.knownHosts (the system-wide
  # /etc/ssh/ssh_known_hosts that root's ssh reads) rather than
  # nix.buildMachines.publicHostKey: that option is documented as base64-wrapped
  # host-key *file* content, and the accepted encoding has moved between Nix
  # versions.
  builderHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM4wW7XvqUoW8L5GL8UU/A4Pst20A0ghQzSQdZtlg2t5";
in
{
  config = mkIf cfg.enable {
    programs.ssh.knownHosts.late-sh = {
      hostNames = [ "late.sh" ];
      publicKey = builderHostKey;
    };

    sops.secrets."nix-builder-key" = {
      sopsFile = config.lib.neg.path "secrets/nix-builder-key.sops.yaml";
      # The daemon opens the connection as root; nobody else needs the key.
      owner = "root";
      mode = "0400";
    };

    nix.distributedBuilds = true;
    nix.buildMachines = [
      {
        hostName = "late.sh"; # dual-stack; the A record is what trantor uses (no global IPv6)
        sshUser = "nixbuilder";
        sshKey = config.sops.secrets."nix-builder-key".path;
        systems = [ "x86_64-linux" ];
        maxJobs = 2; # vCPU count of the VPS is the ceiling, not trantor's
        speedFactor = 1; # trantor's 9950X3D is far faster per job
        # No kvm: the VPS has no /dev/kvm, and advertising a feature the host
        # cannot actually run turns into failed nixos-test builds instead of
        # jobs that simply stay local.
        supportedFeatures = [
          "big-parallel"
          "benchmark"
          "nixos-test"
        ];
        # ssh-ng speaks the daemon protocol and honours builders-use-substitutes;
        # fall back to "ssh" if the builder's Nix is too old to serve it.
        protocol = "ssh-ng";
      }
    ];
  };
}
