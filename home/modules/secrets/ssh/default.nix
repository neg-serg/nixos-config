_: {
  # Start a user-scoped ssh-agent managed by Home Manager
  services.ssh-agent.enable = true;

  # Ensure interactive shells and apps see the same socket path
  # as the systemd user units (also set via environment.d in keyring.nix).
  # This avoids cases where SSH_AUTH_SOCK is unset in shells, causing
  # ssh-add/ssh to fail even when the agent service is running.
  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-agent";

  # OpenSSH config: auto-add keys to the agent on first use
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # HM rename: moved to per-match settings. Keep defaults for now.
    matchBlocks = {
      "*" = {
        addKeysToAgent = "yes"; # AddKeysToAgent yes
      };
    };
  };
}
