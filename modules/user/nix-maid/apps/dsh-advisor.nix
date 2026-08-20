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

  # dsh-advisor: peer-shadow quality advisor — local Ollama model watches the
  # agent on pre-step and injects one short advice when it matters. Mounted in
  # the AGENT plane (see dsh-liangshen-fork/agent.cordis.yml row) where
  # agent/pre-step exists — NO host-plane patch row. The package is a plain
  # directory in the profile node_modules (pnpm is intentionally not used —
  # the @deepseek-ai store symlink makes pnpm writes fail with EROFS, see
  # dsh-market.nix). Files are written only when missing, so local tweaks
  # survive; to re-apply a changed copy from this module, delete
  # ~/.dsh/profiles/web/node_modules/dsh-advisor and restart dsh.
  pkg = ./dsh-advisor;

  ensure = pkgs.writeShellScript "dsh-advisor-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PROFILE_DIR="${homeDir}/.dsh/profiles/web"
    P="$PROFILE_DIR/node_modules/dsh-advisor"
    mkdir -p "$P/lib"
    changed=0
    for f in package.json lib/index.js; do
      if [ ! -f "$P/$f" ]; then
        cp "${pkg}/$f" "$P/$f"
        changed=1
      fi
    done
    if [ "$changed" = 1 ]; then
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      ${pkgs.neg.dsh-restart}/bin/dsh-restart
    fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm.
  system.activationScripts.dshAdvisor = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the package when dsh boots.
  systemd.user.services.dsh-advisor = {
    enable = true;
    description = "dsh-advisor — ensure peer-shadow advisor plugin in the dsh web profile";
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
