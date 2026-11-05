##
# Module: system/systemd/journal-filters
# Purpose: drop a few known-harmless system-service log lines before they hit
#          the journal. systemd 252+ can filter per unit on the MESSAGE field
#          (LogFilterPatterns=), but only for system services — user units are
#          explicitly unsupported, so anything logged from the user bus stays.
#
# Note: dbus-broker's "Ignoring duplicate name" noise comes from the *user*
# bus (dbus-broker.service under user@1000.service) and cannot be filtered
# here; the system bus logs none of it. The real fix is nixpkgs issue #303078
# (open PRs #549241 and #573943).
#
# Patterns are POSIX ERE matched against MESSAGE. They are written without
# literal spaces (`[[:space:]]`): the unit value is a whitespace-separated
# list, so a pattern containing a space would be split into two patterns and
# neither would match.
{ ... }:
{
  systemd.services.systemd-logind.serviceConfig.LogFilterPatterns = [
    # logind parses /boot/loader/entries for `reboot --boot-loader-entry`, and
    # NixOS generation titles ("Generation N NixOS Zokor ...") are not valid
    # version strings — one warning per entry per boot.
    "^/boot/loader/entries/.*is[[:space:]]not[[:space:]]a[[:space:]]valid[[:space:]]version"
  ];
  systemd.services.accounts-daemon.serviceConfig.LogFilterPatterns = [
    # systemd-homed is not enabled; accounts-daemon still probes the userdb
    # endpoint and logs one NameHasNoOwner warning per query round.
    "^couldn't[[:space:]]list[[:space:]]homed[[:space:]]users"
  ];
  systemd.services.systemd-tmpfiles-setup.serviceConfig.LogFilterPatterns = [
    # /zero is owned by neg while the /zero/ai and /zero/sync ZFS datasets are
    # root-owned; tmpfiles flags the ownership transition on every boot. The
    # paths are intentional (services write there as root), so filter the
    # warning instead of changing dataset ownership.
    "^Detected[[:space:]]unsafe[[:space:]]path[[:space:]]transition[[:space:]]/zero"
  ];
}
