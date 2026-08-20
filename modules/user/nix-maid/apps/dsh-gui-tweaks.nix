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

  # dsh-gui-tweaks: client-only GUI behavior tweaks for the dsh web profile —
  # 1) number-key answers in ask-user question dialogs, Enter confirms the
  # selection (clicks Next/Submit), 2) bash tool rows expand by default,
  # 3) bash terminal output cap raised to min(60vh, 720px) with internal
  # scroll (full output reachable, screen not eaten), 4) composer input focused by
  # default (on tab/window focus, session switch, fresh composer mount),
  # 5) todo_write calls render as a todo list card (status glyphs, counts,
  # progress bar, result line) instead of the stock one-line summary row,
  # 6) ask_user_question calls render as a question card (questions, options,
  # chosen answers highlighted) instead of the raw JSON result,
  # 7) long expanded content bounded: assistant "Think" rows collapse by
  # default (expand on click), markdown code blocks height-capped with an
  # internal scrollbar, 8) sidebar logo row (brand + fold toggle) hidden in
  # every state so the column starts at New Session,
  # 9) composer (chat input) gets emacs-style editing keys (C-a/C-e line
  # edges, C-k/C-u kill, C-y yank, C-p/C-n prompt history, M-f/M-b words,
  # ...) on physical key codes, RU layout safe.
  #
  # Canonical source is the dsh-web-ui fork checkout (packages/dsh-gui-tweaks):
  # the profile node_modules entry is a symlink into it, same pattern as
  # dsh-terminal-ui in dsh-market.nix, so source edits apply on the next page
  # refresh — no rebuild needed. If the fork checkout is missing the plugin is
  # skipped with a warning (fresh machine before `git clone`).
  forkPackage = "${homeDir}/src/1st-level/@projects/dsh-web-ui/packages/dsh-gui-tweaks";

  ensureTweaks = pkgs.writeShellScript "dsh-gui-tweaks-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        T="$PROFILE_DIR/node_modules/dsh-gui-tweaks"
        if [ -d "${forkPackage}" ]; then
          # Replace a plain copy (from before the fork migration) with the symlink.
          if [ ! -L "$T" ]; then
            rm -rf -- "$T" 2>/dev/null || true
          fi
          ln -sfn "${forkPackage}" "$T"
        else
          echo "dsh-gui-tweaks: fork checkout missing at ${forkPackage} — plugin not installed" >&2
        fi
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'gui-tweaks' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-gui-tweaks - number-key answers + Enter confirmation in question
    # dialogs, bash tool rows expanded by default, bash output bounded,
    # composer input focused by default, todo_write rendered as a todo list
    # card, ask_user_question rendered as a question card, Think rows collapsed
    # and code blocks height-capped (module: dsh-gui-tweaks.nix).
    - insert:
        - id: gui-tweaks
          name: dsh-gui-tweaks
    YAML
        fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure. Runs after the market
  # ensure so a one-time pnpm install there cannot wipe the plugin dir first.
  system.activationScripts.dshGuiTweaks = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureTweaks} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-gui-tweaks = {
    enable = true;
    description = "dsh-gui-tweaks — ensure GUI behavior tweaks in the dsh web profile";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureTweaks;
    };
  };
}
