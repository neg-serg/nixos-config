{
  config,
  lib,
  pkgs,
  neg,
  ...
}:
let
  ai = config.features.dev.ai;
in
{
  # Herdr — terminal workspace manager / runtime for AI coding agents
  # (workspaces, tabs, panes, git-worktree checkouts, agent state in the
  # sidebar, sessions that survive detach). The agent workflow migration is
  # documented in docs/howto/herdr.md: dsh TUI sessions run inside Herdr
  # panes, dsh-worktree can open new trees as Herdr workspaces, and the
  # dsh-herdr plugin reports working/idle/blocked state to the server.
  #
  # The config is deployed as a live link (neg.live): editing
  # files/herdr/config.toml in the repo applies after
  # `herdr server reload-config`, no rebuild needed.
  config = lib.mkIf (ai.enable && ai.herdr.enable) (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.herdr # Terminal workspace manager / agent runtime (sessions survive detach)
        ];
      }
      (neg.mkHomeFiles {
        ".config/herdr/config.toml".source = neg.live "files/herdr/config.toml";
      })
    ]
  );
}
