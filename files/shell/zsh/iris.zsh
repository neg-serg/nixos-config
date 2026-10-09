# iris — terminal session wrapper with editor-style suggestions
# (https://github.com/versenilvis/iris, packaged here in packages/iris).
#
# `iris init zsh` prints two blocks and both are needed:
#   * in the outer shell (no IRIS_PID) it execs iris, which then drives the
#     real shell through a pty — that is why this file is sourced first in
#     .zshrc: the outer shell should exec before paying for zinit/p10k;
#   * in the child shell iris spawns (IRIS_PID/IRIS_FD set) it installs the
#     ZLE and ipc hooks that feed the line, cwd and aliases back to iris.
# The generated script checks interactivity, a tty, nesting and IRIS_RESCUE
# (which iris sets itself when it crashes and falls back to a plain shell).
# The one guard added here: the binary must exist — distrobox, containers and
# remote hosts have no Nix store mount.
if (( $+commands[iris] )); then
  eval "$(iris init zsh)"
fi
