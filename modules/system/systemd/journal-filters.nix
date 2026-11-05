##
# Module: system/systemd/journal-filters
# Purpose: drop a few known-harmless system-service log lines before they hit
#          the journal. systemd 252+ can filter per unit on the MESSAGE field
#          (LogFilterPatterns=), but only for system services — user units are
#          explicitly unsupported, so anything logged from the user bus stays.
#
# Patterns are POSIX ERE matched against MESSAGE. They are written without
# literal spaces (`[[:space:]]`): the unit value is a whitespace-separated
# list, so a pattern containing a space would be split into two patterns and
# neither would match.
{ ... }:
{
  systemd.services.dbus-broker.serviceConfig.LogFilterPatterns = [
    # Every package with a D-Bus service file is linked both into
    # /run/current-system/sw/share and into the dbus-consolidated tree, so
    # dbus-broker-launch reports the same name twice on every startup.
    "^Ignoring[[:space:]]duplicate[[:space:]]name"
    # adw-bluetooth 1.2.0 installs com.ezratweaver.AdwBluetoothDaemon.dbus.service;
    # the file name must equal the bus name (no `.dbus` suffix). Harmless: the
    # daemon is started by its systemd user unit, not by D-Bus activation.
    "^Service[[:space:]]file[[:space:]].*is[[:space:]]not[[:space:]]named[[:space:]]after[[:space:]]the[[:space:]]D-Bus[[:space:]]name"
  ];
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
