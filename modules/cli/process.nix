{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.entr # run arbitrary commands when files change
    pkgs.inotify-tools # command-line utilities for the inotify Linux kernel subsystem
    pkgs.lsof # list open files and the processes that opened them
    pkgs.parallel # shell tool for executing jobs in parallel
    pkgs.procps # utilities for monitoring and managing system processes (top, ps, etc.)
    pkgs.progress # show progress for coreutils (cp, mv, dd, tar, etc.)
    pkgs.psmisc # small utilities that use the proc filesystem (killall, fuser, pstree)
    pkgs.pueue # command-line task management tool for sequential and parallel execution
    pkgs.pv # monitor the progress of data through a pipeline
    pkgs.reptyr # tool for taking an existing running program and attaching it to a new terminal
  ];
}
