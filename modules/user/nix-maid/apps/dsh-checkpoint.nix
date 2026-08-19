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

  # dsh-checkpoint: context checkpoint / soft rewind — replace intermediate
  # exploration with a concise report. Server plugin, host plane — same
  # pattern as dsh-osm. The package is a plain directory in the profile
  # node_modules (pnpm is intentionally not used — the @deepseek-ai store
  # symlink makes pnpm writes fail with EROFS, see dsh-market.nix),
  # registered through a profile patch insert row. Files are written only
  # when missing, so local tweaks survive; to re-apply a changed copy from
  # this module, delete ~/.dsh/profiles/web/node_modules/dsh-checkpoint and
  # restart dsh.
  pkg = ./dsh-checkpoint;

  ensure = pkgs.writeShellScript "dsh-checkpoint-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-checkpoint"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-checkpoint' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-checkpoint - context checkpoint / soft rewind
    # (module: dsh-checkpoint.nix).
    - insert:
        - id: checkpoint
          name: dsh-checkpoint
    YAML
          changed=1
        fi
        if [ "$changed" = 1 ]; then
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          ${pkgs.neg.dsh-restart}/bin/dsh-restart
        fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm.
  system.activationScripts.dshCheckpoint = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-checkpoint = {
    enable = true;
    description = "dsh-checkpoint — ensure checkpoint/rewind tool in the dsh web profile";
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
