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

  # dsh-plan-format-validator: gate exit_plan_mode plans on shape (heading +
  # sections + non-empty body) before user review. Same pattern as dsh-read-tags.
  pkg = ./dsh-plan-format-validator;

  ensure = pkgs.writeShellScript "dsh-plan-format-validator-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-plan-format-validator"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-plan-format-validator' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-plan-format-validator - gate exit_plan_mode plan shape
    # (module: dsh-plan-format-validator.nix).
    - insert:
        - id: plan-format-validator
          name: dsh-plan-format-validator
    YAML
          changed=1
        fi
        if [ "$changed" = 1 ]; then
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          ${pkgs.neg.dsh-restart}
        fi
  '';
in
{
  system.activationScripts.dshPlanFormatValidator = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  systemd.user.services.dsh-plan-format-validator = {
    enable = true;
    description = "dsh-plan-format-validator — gate exit_plan_mode plan shape before user review";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensure;
    };
  };
}
