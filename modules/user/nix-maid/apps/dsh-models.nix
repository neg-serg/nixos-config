{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser homeDir;
  systemdUser = import (config.lib.neg.path "lib/systemd-user.nix") { inherit lib; };

  # dsh model policy: keep the deployment on the V4.1 route everywhere.
  #
  # @deepseek-ai/dsh-llm-deepseek ships four catalog entries — the V4.1 id
  # (`deepseek-flash`, the only one with image input and the in-history
  # system-prompt update) plus three V4-era ones (`deepseek-v4-flash`,
  # `deepseek-v4-pro`, `deepseek-v4-flash-vision-exp`) that the model picker
  # still offers and that describe themselves with V4 capability metadata.
  # The provider config is settings-backed (namespace `llm-deepseek`, same as
  # `llm-pi-ai` in the user's settings), so one managed block in
  # ~/.dsh/settings.yaml narrows the catalog for every profile at once — web
  # GUI, TUI, subagents and the title model — and hot-reloads without a restart.
  #
  # The second block pins the default model and thinking level for new sessions
  # in every profile. Runtime switches (the session model picker, and the
  # /fast, /smart and /effort commands from dsh-mode) change the same keys, so
  # they survive only until the next rebuild or login, when the managed value
  # is restored.
  #
  # The user owns settings.yaml, so blocks are marker-delimited and only they
  # are rewritten; an existing hand-written section with the same top-level key
  # is replaced wholesale (the service's schema fills the rest from defaults,
  # since the composed rows carry no config of their own).
  blocks = [
    {
      marker = "dsh-models";
      key = "llm-deepseek";
      body = ''
        # dsh-models: begin (managed by modules/user/nix-maid/apps/dsh-models.nix)
        # V4.1-only provider catalog: the shipped list also offers deepseek-v4-flash,
        # deepseek-v4-pro and deepseek-v4-flash-vision-exp, which carry V4-era
        # capability metadata (text-only, no in-history system-prompt update).
        llm-deepseek:
          models:
            - id: deepseek-flash
              name: DeepSeek-V41-Flash
              inputModalities:
                - text
                - image
        # dsh-models: end
      '';
    }
    {
      marker = "dsh-agent-default-model";
      key = "agent-default-model";
      body = ''
        # dsh-agent-default-model: begin (managed by modules/user/nix-maid/apps/dsh-models.nix)
        # Deployment-wide default for new sessions: the V4.1 route only. Runtime
        # switches (/fast, /smart, /effort, the session model picker) revert on
        # the next rebuild or login.
        agent-default-model:
          provider: deepseek-official
          model: deepseek-flash
          reasoningEffort: high
        # dsh-agent-default-model: end
      '';
    }
  ];

  blocksJson = pkgs.writeText "dsh-models-blocks.json" (builtins.toJSON blocks);

  patch = ./dsh-models-settings.py;

  ensure = pkgs.writeShellScript "dsh-models-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    ${lib.getExe pkgs.python3} ${patch} "${homeDir}/.dsh/settings.yaml" ${blocksJson}
  '';
in
{
  # Runs on every rebuild (as the user, so the settings file stays user-owned)
  # and on every login — same pattern as dsh-tui-ru.
  system.activationScripts.dshModels = systemdUser.mkUserActivation {
    inherit pkgs;
    user = mainUser;
    home = homeDir;
    script = ensure;
  };

  systemd.user.services.dsh-models = systemdUser.mkUserOneshot {
    description = "dsh-models — keep ~/.dsh/settings.yaml on the V4.1 model policy";
    script = ensure;
    after = [ "network.target" ];
  };
}
