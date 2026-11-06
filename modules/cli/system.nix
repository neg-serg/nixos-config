{ config, pkgs, ... }:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  environment.systemPackages = [
    # Process management
    pkgs.entr # run arbitrary commands when files change
    pkgs.inotify-tools # command-line utilities for the inotify Linux kernel subsystem
    pkgs.lsof # list open files and the processes that opened them
    pkgs.parallel # shell tool for executing jobs in parallel
    pkgs.procps # utilities for monitoring and managing system processes (top, ps, etc.)
    pkgs.progress # show progress for coreutils (cp, mv, dd, tar, etc.)
    pkgs.psmisc # small utilities that use the proc filesystem (killall, fuser, pstree)
    pkgs.pv # monitor the progress of data through a pipeline
    pkgs.reptyr # tool for taking an existing running program and attaching it to a new terminal

    # Log viewer: kept in the `tools` devshell for project work and built on
    # demand here, so the binary is not part of every switch. The other
    # monitoring tools live in modules/cli/monitoring.nix.
    (onDemand {
      name = "lnav";
      attr = "lnav";
    })

    # Containers
    pkgs.oxker # TUI to view and control containers (Docker API; /var/run/docker.sock points at the podman socket)

    # Shell enhancements
    pkgs.expect # tool for automating interactive applications
    pkgs.rlwrap # readline wrapper that provides editing and history for any command
  ];
}
