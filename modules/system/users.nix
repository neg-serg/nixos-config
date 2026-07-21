{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.users.main or { };
  mainName = cfg.name or "neg";
  mainUid = cfg.uid or 1000;
  mainGroup =
    let
      g = cfg.group or null;
    in
    if g == null then mainName else g;
  mainGid = cfg.gid or 1000;
  mainDesc = cfg.description or "Neg";
  mainAuthorizedKeys =
    cfg.opensshAuthorizedKeys or [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKg+t07fFxKPqtDR3rRpvS6Tc9Rrh5yv7fC5GFrBtyK neg@odin"
    ];
  mainHashedPasswordFile =
    cfg.hashedPasswordFile;
with rec {
  groupExists = grp: builtins.hasAttr grp config.users.groups;
  groupsIfExist = builtins.filter groupExists;
};
{
  options.users.main = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "neg";
      description = "Primary (login) user name used across the system.";
      example = "alice";
    };
    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "UID for the primary user.";
      example = 1000;
    };
    group = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Primary group name for the main user (defaults to users.main.name).";
      example = "alice";
    };
    gid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "GID for the main user's primary group.";
      example = 1000;
    };
    description = lib.mkOption {
      type = lib.types.str;
      default = "Neg";
      description = "GECOS/real name for the primary user.";
      example = "Alice Example";
    };
    opensshAuthorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKg+t07fFxKPqtDR3rRpvS6Tc9Rrh5yv7fC5GFrBtyK neg@odin"
      ];
      description = "Authorized SSH public keys for the primary user.";
    };
    hashedPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to file containing shadow-compatible password hash for the primary user. Prefer this over hashedPassword to avoid storing the hash in the Nix store. SOPS-managed path recommended.";
    };
  };

  config = {
    # Simplify group NSS lookup: remove systemd module + [success=merge].
    # The systemd NSS module can interfere early in boot (chicken-and-egg
    # with PID 1), causing getgrnam() to fail for static groups like
    # "netdev".  Static groups are served by files(5) only.
    # See also: https://github.com/bus1/dbus-broker/wiki/Policy#credentials
    system.nssDatabases.group = [ "files" ];

    users = {
      users.root.hashedPassword = lib.mkDefault "*"; # lock root account
      users.${mainName} = {
        isNormalUser = true;
        uid = mainUid;
        group = mainGroup;
        openssh.authorizedKeys.keys = mainAuthorizedKeys;
        hashedPasswordFile = lib.mkIf (mainHashedPasswordFile != null) mainHashedPasswordFile;
        description = mainDesc;
        extraGroups = groupsIfExist [
          "audio"
          "dialout"
          "docker"
          "greeter"
          "i2c"
          "input"
          "libvirtd"
          "render"
          "networkmanager"
          "systemd-journal"
          "tss"
          "video"
          "wheel"
          "adbusers"
          "kvm"
          "tailscale"
        ];
      };
      defaultUserShell = pkgs.zsh; # Z shell
      groups.${mainGroup}.gid = mainGid;
      groups.netdev = {
        gid = 977;
      }; # Referenced by avahi-dbus.conf policy
      groups.sing-box = {
        gid = 976;
      }; # Referenced by sing-box-split-dns.conf policy
      users.sing-box = {
        isSystemUser = true;
        uid = 984;
        group = "sing-box";
        description = "sing-box proxy platform (dbus policy)";
      };
    };
  };
}
