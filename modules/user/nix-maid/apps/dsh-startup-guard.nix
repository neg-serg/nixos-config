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

  # dsh-startup-guard (npm, third-party) over-reports on dsh 0.1.5:
  #
  # 1. `compositionPreflight` concatenates the entry ids of every patch file
  #    in the composed stack and flags *any* repeat as a loader-level boot
  #    failure. Re-declaring an earlier layer's id IS the patch override
  #    mechanism: upstream's own @deepseek-ai/dsh-base and @deepseek-ai/dsh-web-app
  #    both ship tool-bash/tools/system-prompt/..., the profile patch overrides
  #    web-runtime/agent-presets, and the aggregate @linxin666/dsh-web-ui-all
  #    re-declares its sub-plugin rows. The tree boots clean, so the guard
  #    reported 37 web + 1 tui issues on every boot. guard-patch.mjs scopes the
  #    duplicate check to one patch file (a same-file repeat stays fatal, so
  #    strict mode still blocks real authoring bugs) — idempotent, with an
  #    .orig backup and a sentinel marker.
  #
  # 2. The host-smoke harness calls plugin.apply() on every third-party host
  #    entry through a mock ctx. dsh-pathlink's default export is a Service
  #    class, so `apply` resolves to Function.prototype.apply and throws
  #    "Class constructor PathlinkService cannot be invoked without 'new'";
  #    dsh-memento's apply() succeeds in the real tree. Both are checker false
  #    positives, suppressed through the guard's supported `exclude` key.
  #
  # The config also keeps the user's mode/autoRepairComposition choices.
  guardConfig = ./dsh-startup-guard-assets/guard-config.json;
  patcher = ./dsh-startup-guard-assets/guard-patch.mjs;

  # Re-apply both on every rebuild and login: a pnpm re-install of the plugin
  # overwrites guard-core.mjs and the config, so a one-shot edit would not
  # survive. Idempotent and failure-tolerant — the guard itself must never be
  # able to break activation.
  runPatch = pkgs.writeShellScript "dsh-startup-guard-patch" ''
    set +e
    ${pkgs.coreutils}/bin/install -m 0600 ${guardConfig} "${homeDir}/.dsh/dsh-startup-guard.json" \
      || echo "dsh-startup-guard: config write failed" >&2
    for core in ${homeDir}/.dsh/profiles/*/node_modules/dsh-startup-guard/lib/guard-core.mjs; do
      [ -f "$core" ] || continue
      ${lib.getExe pkgs.nodejs} ${patcher} "$core" \
        || echo "dsh-startup-guard: patch failed for $core" >&2
    done
    exit 0
  '';
in
{
  # As the user, so the profile files stay user-owned (pnpm must keep being
  # able to update the bundles). Same pattern as dsh-web-en / dsh-osm.
  system.activationScripts.dshStartupGuard = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${runPatch} || true
  '';

  # ...and on every login, so the patch survives plugin re-installs made after
  # the last rebuild.
  systemd.user.services.dsh-startup-guard = {
    enable = true;
    description = "dsh-startup-guard — per-file duplicate-id heuristic + smoke false-positive suppression";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = runPatch;
    };
  };
}
