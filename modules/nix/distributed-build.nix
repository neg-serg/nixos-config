##
# Module: nix/distributed-build
# Purpose: let builds run on a second x86_64 machine over SSH instead of queueing
# behind trantor's `max-jobs = 1`. That cap is deliberate (settings.nix: two
# 16-core jobs blew the 40G memcg cap), so one heavy build leaves the local
# daemon idle; a second box fills the gap with unrelated small derivations.
# Declared builders are best-effort: when the host is unreachable Nix logs the
# failure and builds locally. `builders-use-substitutes = true` (settings.nix)
# is what makes the split pay off — the builder pulls inputs from its own
# substituters instead of receiving them over the SSH link.
#
# Disabled by default, and the host below is a placeholder: the only candidate
# inspected so far (late.sh) is an SSH "terminal clubhouse" TUI, not a machine —
# it answers with an install banner and `exec request failed on channel 0`, so it
# can never run `nix-daemon --stdio`. Probed 2026-10-25: the local side is fine
# (Nix listed the machine with its features and tried ssh-ng), only the peer was
# wrong. Before enabling: point hostName at a real builder, refresh the host key
# (`ssh-keyscan -t ed25519 <host>`), and have the ssh user's public key here in
# authorized_keys plus that user in the host's nix.settings.trusted-users.
# Key options: features.nix.remoteBuilder.enable (default false).
# Dependencies: sops.secrets."nix-builder-key" — secrets/nix-builder-key.sops.yaml
# holds the passphrase-less ed25519 key the *daemon* (root, not neg) uses to log
# in; only materialised while the flag is on.
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.nix.remoteBuilder;

  # Placeholder host key, `ssh-keyscan -t ed25519 late.sh`
  # (SHA256:Tc7aeaaQulKJeF3C/zd2BKvq/KgaQTHyMPNa3s9K+aE) — refresh it together
  # with hostName once a real builder exists. It goes into
  # programs.ssh.knownHosts (the system-wide /etc/ssh/ssh_known_hosts that root's
  # ssh reads) rather than nix.buildMachines.publicHostKey: that option is
  # documented as base64-wrapped host-key *file* content, and the accepted
  # encoding has moved between Nix versions.
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
        hostName = "late.sh"; # placeholder: late.sh cannot build, see the header
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
