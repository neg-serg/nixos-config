{
  pkgs,
  ...
}:
let
  # System users whose shell defaults to pkgs.shadow (a shellPackage).
  # Each of these adds a copy of shadow to environment.systemPackages
  # via the systemShells mechanism in users-groups.nix (line 662-666).
  #
  # We override their shell to a PATH (${pkgs.shadow}/bin/nologin) instead
  # of the pkgs.shadow PACKAGE.  Paths don't pass types.shellPackage.check,
  # so systemShells skips them, eliminating the duplication.
  #
  # The nologin binary is still available because programs/shadow.nix
  # adds pkgs.shadow to systemPackages once (when users.mutableUsers).

  systemUsers = [
    # Core system users
    "nobody"
    "nscd"
    "pcscd"
    "polkituser"
    "rtkit"
    "sshd"
    "systemd-coredump"
    "systemd-network"
    "systemd-oom"
    "systemd-resolve"
    "systemd-timesync"
    "unbound"

    # Service users
    "adguardhome"
    "avahi"
    "flatpak"
    "fwupd-refresh"
    "greeter"
    "messagebus"
    "shairport"
    "sing-box"
    "vnstatd"
  ];

  # nixbld users removed — auto-allocate-uids handles build users dynamically
  allUsers = systemUsers;

  # Map each user name to a shell override (nologin path instead of package)
  shellOverrides = builtins.listToAttrs (
    map (name: {
      inherit name;
      value.shell = "${pkgs.shadow}/bin/nologin";
    }) allUsers
  );
in
{
  config.users.users = shellOverrides;
}
