# Module: nix-maid/sys/dsh-web-ui-build — keep the dsh web profile's plugin
# bundles in sync with the dsh-web-ui checkout.
#
# The profile serves each plugin's BUILT bundle (lib/client.js); its
# node_modules entries are workspace symlinks into the checkout
# (~/src/1st-level/@projects/dsh-web-ui). Editing src/ of a TS package has no
# effect on the running GUI until tsdown rebuilds lib/ — the classic "fixed in
# src but still shows the old behavior" trap. This watcher runs
# scripts/watch-plugin-libs.mjs (one tsdown per changed package, debounced) so
# the profile always serves fresh bundles after an edit: just refresh the page.
# Manual one-off: just dsh-ui-build; staleness check: just dsh-ui-stale.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.users.main.name or "neg";
  userData = lib.attrByPath [ "users" "users" user ] { } config;
  homeDir = lib.attrByPath [ "home" ] "/home/${user}" userData;
  checkout = "${homeDir}/src/1st-level/@projects/dsh-web-ui";
in
{
  systemd.user.services.dsh-web-ui-watch = {
    enable = true;
    description = "dsh-web-ui plugin lib watcher — rebuild tsdown bundles on src change";
    after = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 5;
      ExecStart = "${lib.getExe pkgs.nodejs} ${checkout}/scripts/watch-plugin-libs.mjs";
      WorkingDirectory = checkout;
    };
  };
}
