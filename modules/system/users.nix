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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKg+t07fFxKPqtDR3rRpvS6Tc9Rrh5yv7fC5GFrBtyK neg@telfir"
    ];
  mainHashedPassword =
    cfg.hashedPassword
      or "$6$dy0VIe3yFCwdxh2q$CkgfitafpeqFwYn7fqmR/CRP29G/h9sBcN8sOPSXfgkCeraXA6B8VOoJLrsaktUsSnfHbC0RqDHcnnUCtICF4.";
in
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
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKg+t07fFxKPqtDR3rRpvS6Tc9Rrh5yv7fC5GFrBtyK neg@telfir"
      ];
      description = "Authorized SSH public keys for the primary user.";
    };
    hashedPassword = lib.mkOption {
      type = lib.types.str;
      default = "$6$dy0VIe3yFCwdxh2q$CkgfitafpeqFwYn7fqmR/CRP29G/h9sBcN8sOPSXfgkCeraXA6B8VOoJLrsaktUsSnfHbC0RqDHcnnUCtICF4.";
      description = "Shadow-compatible password hash for the primary user (use mkpasswd -m sha-512).";
    };
  };

  config = {
    users = {
      users.root.hashedPassword = "*"; # lock root account
      users.${mainName} = {
        isNormalUser = true;
        uid = mainUid;
        group = mainGroup;
        openssh.authorizedKeys.keys = mainAuthorizedKeys;
        hashedPassword = mainHashedPassword;
        description = mainDesc;
        extraGroups = groupsIfExist [
          "audio"
          "dialout"
          "docker"
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
        ];
      };
      defaultUserShell = pkgs.zsh; # Z shell
      groups.${mainGroup}.gid = mainGid;
    };
  };
}
