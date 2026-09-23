{ ... }:
{
  programs.zsh = {
    enable = true;
    # The global rc built by this module is not free: measured with the real zsh,
    # /etc/zshrc alone cost ~45 ms per interactive shell ("globals only, empty
    # ZDOTDIR" 50 ms vs 4 ms bare, 2026-09-23) — a second compinit on top of the
    # user's own (files/shell/zsh/01-init.zsh, compiled dump in ~/.cache/zsh) and a
    # coreutils LS_COLORS eval. Both have per-user counterparts, so the global ones
    # are off; shells that do NOT load the user config (root, `zsh -f -i`) lose
    # those two only. Completion functions themselves stay on fpath either way.
    enableGlobalCompInit = false;
    enableLsColors = false;
    interactiveShellInit = ''
      # Carapace completions. The env var and the format zstyle stay in the global rc
      # (cheap, and CARAPACE_BRIDGES must be exported before carapace runs), but
      # `carapace _carapace` itself moved out of it: spawning the binary cost ~10 ms on
      # every interactive shell (zprof, 2026-09-23) and the compdefs it registers here
      # were thrown away by the later compinit anyway. files/shell/zsh/03-completion.zsh
      # sources carapace after compinit, deferred — which is where it can wire up.
      export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
      zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'

    '';
  };
}
