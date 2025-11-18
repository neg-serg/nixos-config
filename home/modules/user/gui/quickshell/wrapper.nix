{
  lib,
  pkgs,
  config,
  qsProvider ? null,
  ...
}:
with lib; let
  mkQuickshellWrapper = import ../../../../../lib/quickshell-wrapper.nix {
    inherit lib pkgs;
  };
  qsPkg =
    if qsProvider != null
    then (qsProvider pkgs)
    else null;
  quickshellWrapped =
    if qsPkg == null
    then null
    else mkQuickshellWrapper {qsPkg = qsPkg;};
in
  mkIf (config.features.gui.enable && (config.features.gui.qt.enable or false) && (config.features.gui.quickshell.enable or false) && (! (config.features.devSpeed.enable or false))) {
    # Expose the wrapped package for other modules (e.g., systemd service ExecStart)
    neg.quickshell.wrapperPackage = quickshellWrapped;
  }
