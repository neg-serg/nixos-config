{
  neg,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    inputs.nix-maid.nixosModules.default # user configuration framework (nix-maid)
  ]
  ++ neg.importDir {
    dir = ./.; # mutt-conf/ and scripts/ are data directories — importDir skips them
    includeDirs = true;
  };

  users.users.neg.maid = { };

  # Activation script to force restart maid-activation for 'neg'.
  # This ensures user configs are reapplied on every switch, working around
  # NixOS's behavior of not automatically restarting user services reliably.
  system.activationScripts.maidForceRestart = lib.stringAfter [ "users" ] ''
    if [ -e /run/user/1000 ]; then
      echo "Restarting maid-activation for user 1000..."
      (${lib.getExe' pkgs.util-linux "runuser"} -u neg -- ${lib.getExe' pkgs.bash "bash"} -c "XDG_RUNTIME_DIR=/run/user/1000 ${lib.getExe' pkgs.systemd "systemctl"} --user restart --no-block maid-activation.service" >/dev/null 2>&1 &) || true
    fi
  '';
}
