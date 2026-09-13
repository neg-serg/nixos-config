{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  cfg = config.features.gpg;

  # Custom Pinentry Wrapper
  # Injects Wayland/DBus env vars for reliable GUI prompting
  pinentryQt = pkgs.writeShellApplication {
    name = "pinentry-qt-with-env";
    checkPhase = "true";
    text =
      builtins.replaceStrings
        [ "@COREUTILS@" "@PINENTRY@" ]
        [ "${pkgs.coreutils}" (lib.getExe pkgs.pinentry-qt) ]
        (builtins.readFile ./pinentry-qt-with-env.sh);
  };

  # GPG Agent Config
  # Note: pinentry-program path must be absolute
  agentConf = ''
    pinentry-program ${lib.getExe pinentryQt}
    allow-loopback-pinentry
    default-cache-ttl 60480000
    max-cache-ttl 60480000
    enable-ssh-support
  '';

  # Scdaemon Config
  scdaemonConf = ''
    disable-ccid
    pcsc-shared
    reader-port "Yubico Yubi"
  '';
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        # 2. Systemd Service
        # Replacing HM's services.gpg-agent
        systemd.user.services.gpg-agent = {
          description = "GnuPG cryptography agent";
          documentation = [ "man:gpg-agent(1)" ];
          requires = [ "gpg-agent.socket" ];
          after = [
            "gpg-agent.socket"
            "gui-session.target"
          ];
          # We want it to be socket activated primarily, but can be started by target
          wantedBy = [ "default.target" ];

          serviceConfig = {
            ExecStart = "${lib.getExe' pkgs.gnupg "gpg-agent"} --supervised"; # Modern release of the GNU Privacy Guard, a GPL OpenPGP im...
            ExecReload = "${lib.getExe' pkgs.gnupg "gpgconf"} --reload gpg-agent"; # Modern release of the GNU Privacy Guard, a GPL OpenPGP im...
          };
        };

        systemd.user.sockets.gpg-agent = {
          description = "GnuPG cryptography agent socket";
          documentation = [ "man:gpg-agent(1)" ];
          listenStreams = [ "%t/gnupg/S.gpg-agent" ];
          socketConfig = {
            FileDescriptorName = "std";
            SocketMode = "0600";
            DirectoryMode = "0700";
          };
          wantedBy = [ "sockets.target" ];
        };

        systemd.user.sockets.gpg-agent-ssh = {
          description = "GnuPG cryptography agent SSH socket";
          documentation = [ "man:gpg-agent(1)" ];
          listenStreams = [ "%t/gnupg/S.gpg-agent.ssh" ];
          socketConfig = {
            FileDescriptorName = "ssh";
            SocketMode = "0600";
            DirectoryMode = "0700";
            Service = "gpg-agent.service";
          };
          wantedBy = [ "sockets.target" ];
        };

        # Include packages
        environment.systemPackages = [
          pkgs.gnupg # GNU Privacy Guard - encryption and signing tool
          pkgs.pinentry-qt # Qt-native pinentry for GPG
          pinentryQt # custom wrapper script for pinentry-qt with env injection
        ];
      }

      # 1. Config Files via Maid
      (neg.mkHomeFiles {
        ".gnupg/gpg-agent.conf".text = agentConf;
        ".gnupg/scdaemon.conf".text = scdaemonConf;
        # Ensure permissions for GPG dir? Maid handles file creation, but usually gnupg handles dir perms on run.
      })
    ]
  );
}
