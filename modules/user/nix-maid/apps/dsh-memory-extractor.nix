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

  # dsh-memory-extractor: session-end memory extraction into memento
  # (draft transcript + LLM stage-one extraction via local Ollama, model
  # switchable through the patch-row config below).
  # Server plugin, host plane — same pattern as dsh-osm. The package is a
  # plain directory in the profile node_modules (pnpm is intentionally not
  # used — the @deepseek-ai store symlink makes pnpm writes fail with EROFS,
  # see dsh-market.nix), registered through a profile patch insert row.
  # Files are written only when missing, so local tweaks survive; to re-apply
  # a changed copy from this module, delete
  # ~/.dsh/profiles/web/node_modules/dsh-memory-extractor and restart dsh.
  pkg = ./dsh-memory-extractor;

  ensure = pkgs.writeShellScript "dsh-memory-extractor-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-memory-extractor"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-memory-extractor' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-memory-extractor - session-end extract into memento (draft + local
    # Ollama LLM step; model is switchable in the config below, e.g. gemma4:12b
    # or deepseek-r1-distill-qwen:14b on this host).
    # (module: dsh-memory-extractor.nix).
    - insert:
        - id: memory-extractor
          name: dsh-memory-extractor
          config:
            model: qwen3:8b-q8_0
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
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm.
  system.activationScripts.dshMemoryExtractor = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-memory-extractor = {
    enable = true;
    description = "dsh-memory-extractor — ensure session-end memory draft in the dsh web profile";
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
