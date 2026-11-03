{
  neg,
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  mainUser = config.lib.neg.mainUser;

  # ── Fast activation ───────────────────────────────────────────────────────
  # nix-maid's activate walks both tmpfiles configurations line by line and
  # forks `echo | grep` for every rule (~2 900 processes for 715 rules) — that
  # is ~3.4 s of the ~3.6 s activation. The two filters below are the same
  # predicates expressed with bash pattern matching, so no process is spawned
  # per line. The rest of the upstream script is used verbatim.
  #
  # The patch runs at *build* time. Reading the upstream output during
  # evaluation (builtins.readFile on a derivation) forced an IFD build of
  # all-maid on every eval; substituteInPlace does the same literal replacement
  # in the build sandbox, and --replace-fail keeps the loud failure when
  # upstream rewrites the lines.
  activateFast = pkgs.runCommand "nix-maid-activate-fast" { } ''
    install -Dm755 ${config.system.build.all-maid}/nix-maid-${mainUser}/bin/activate $out/bin/activate
    substituteInPlace $out/bin/activate \
      --replace-fail 'echo "$path" | grep -q "$state_home/nix-maid/static"' \
                     '[[ $path == *"$state_home/nix-maid/static"* ]]' \
      --replace-fail 'echo "$path" | grep -q "$state_home/nix-maid/.*/static"' \
                     '[[ $path =~ $state_home/nix-maid/.*/static ]]' \
      --replace-fail 'sd-switch --new-units "$config_home/systemd/user" "''${sd_switch_flags[@]}"' \
        '  units_dir="$(realpath "$config_home/systemd/user")"
      marker="$state_home/nix-maid/sd-switch-units"
      if [[ -z "$(${lib.getExe' pkgs.systemd "systemctl"} --user list-units --state=failed --no-legend --plain 2>/dev/null | head -n1)" \
            && -f "$marker" && "$(cat "$marker")" == "$units_dir" ]]; then
        echo ":: units unchanged ($units_dir), sd-switch skipped"
      else
        sd-switch --new-units "$config_home/systemd/user" "''${sd_switch_flags[@]}"
        mkdir -p "$(dirname "$marker")"
        echo "$units_dir" > "$marker"
      fi'
  '';
in
{
  imports = [
    inputs.nix-maid.nixosModules.default # user configuration framework (nix-maid)
  ]
  ++ neg.importDir {
    dir = ./.; # mutt-conf/ and scripts/ are data directories — importDir skips them
    includeDirs = true;
  };

  users.users.neg.maid = { };

  # Use the patched activation script (same content, minus the per-line forks).
  systemd.user.services.maid-activation.script = lib.mkForce ''
    while IFS= read -r line; do
      for var in DBUS_SESSION_BUS_ADDRESS DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR; do
        if [[ "$line" == "$var="* ]]; then
          export "''${line?}"
        fi
      done
    done < <(systemctl --user show-environment 2>/dev/null)

    activation="${activateFast}/bin/activate"
    echo "Using activation: $activation"
    "$activation"
    touch "$XDG_RUNTIME_DIR/maid-started"
  '';

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
