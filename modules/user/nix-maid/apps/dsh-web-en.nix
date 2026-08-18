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

  # The web profile's third-party plugin bundles hardcode Chinese UI strings
  # (spotlight palette titles + tooltips/aria-labels, free-search settings
  # labels, plugin-vetting report text, file-upload truncation notices) that
  # ignore the dsh locale preference. Assets below rewrite those exact
  # literals to English: the translation map (i18n.json) plus the idempotent
  # patcher (patch.mjs, marker-file based — same pattern as dsh-tui-ru).
  i18nJson = ./dsh-web-en-assets/i18n.json;
  patcher = ./dsh-web-en-assets/patch.mjs;

  # Patch every patched bundle under the web profile's node_modules.
  # Idempotent (per-bundle marker files); safe to re-run after plugin
  # re-installs. Also de-Chinese the pet name in ~/.dsh/pet.json (the pet
  # widget is disabled, but the stored name would render if ever re-enabled).
  python3Path = lib.getExe pkgs.python3;
  runPatch = pkgs.writeShellScript "dsh-web-en-patch" ''
    set +e
    ${lib.getExe pkgs.nodejs} ${patcher} ${i18nJson} ${homeDir}/.dsh/profiles/web/node_modules \
      || echo "dsh-web-en: patch failed" >&2
    ${python3Path} - "${homeDir}/.dsh/pet.json" <<'PY'
    import json, sys
    path = sys.argv[1]
    try:
        with open(path, encoding="utf-8") as f:
            pet = json.load(f)
        names = pet.get("names") or {}
        if names.get("whale-girl") == "鲸鱼娘":
            names["whale-girl"] = "Whale Girl"
            with open(path, "w", encoding="utf-8") as f:
                json.dump(pet, f, ensure_ascii=False, indent=2)
                f.write("\n")
    except (OSError, ValueError):
        pass
    PY
    exit 0
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned — pnpm must keep being able to update the bundles). Same
  # pattern as dsh-market-ensure.
  system.activationScripts.dshWebEn = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${runPatch} || true
  '';

  # ...and on every login, so the patch survives plugin re-installs made
  # after the last rebuild.
  systemd.user.services.dsh-web-en = {
    enable = true;
    description = "dsh web profile — apply English UI patch (de-Chinese plugin bundles)";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = runPatch;
    };
  };
}
