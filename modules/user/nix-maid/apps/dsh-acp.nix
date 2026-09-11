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

  # dsh ACP profile: the editor surface (Agent Client Protocol over stdio),
  # used by CodeCompanion in Neovim.
  #
  # The profile needs a manifest and a patch layer only — both bundles resolve
  # from the dsh installation, so there is nothing for pnpm to install. The
  # files are written as real files (not home-file symlinks) because the
  # harness creates node_modules inside the profile directory.
  #
  # The patch pins the @deepseek-ai/dsh-acp-app row: it ships with
  # deepseek-v4-flash, and that pinned model is what the session model picker
  # reports as current. The deployment runs V4.1-Flash only (the global
  # catalog is narrowed by dsh-models.nix), so the row must name the V4.1 id.
  packageJson = pkgs.writeText "dsh-acp-package.json" ''
    {
      "name": "dsh-profile-acp",
      "private": true,
      "dependencies": {},
      "dsh": {
        "profile": {
          "bundles": [
            "@deepseek-ai/dsh-base",
            "@deepseek-ai/dsh-acp-app"
          ]
        }
      }
    }
  '';

  cordisYml = pkgs.writeText "dsh-acp-cordis.yml" ''
    # dsh profile root - an empty entry list. The tree is composed as patches:
    # each bundle in package.json's dsh.profile.bundles, then cordis.patch.yml.
    []
  '';

  patchYml = pkgs.writeText "dsh-acp-cordis.patch.yml" ''
    # dsh ACP profile patch layer (applied after the bundle patches).
    # Pin every session to the V4.1 route: the shipped @deepseek-ai/dsh-acp-app
    # row defaults to the retired deepseek-v4-flash id, which the model picker
    # then reports as the current model. See dsh-models.nix for the catalog.
    - id: acp
      config:
        provider: deepseek-official
        model: deepseek-flash
  '';

  ensure = pkgs.writeShellScript "dsh-acp-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    dir="${homeDir}/.dsh/profiles/acp"
    install -d -m 700 "$dir"
    write() {
      if ! cmp -s "$2" "$dir/$1"; then
        install -m 600 "$2" "$dir/$1"
        echo "dsh-acp: wrote $dir/$1"
      fi
    }
    write package.json ${packageJson}
    write cordis.yml ${cordisYml}
    write cordis.patch.yml ${patchYml}
  '';
in
{
  # Runs on every rebuild (as the user, so the profile stays user-owned) and on
  # every login — same pattern as dsh-models / dsh-market / dsh-tui-ru.
  system.activationScripts.dshAcp = lib.stringAfter [ "users" "dshModels" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  systemd.user.services.dsh-acp = {
    enable = true;
    description = "dsh-acp — keep the ACP profile on the V4.1 route";
    after = [ "network.target" ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensure;
    };
  };
}
