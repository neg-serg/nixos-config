{ pkgs, ... }:
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
    pkgs.pueue # command-line task management tool for sequential and parallel execution
    pkgs.pv # monitor the progress of data through a pipeline
    pkgs.reptyr # tool for taking an existing running program and attaching it to a new terminal

    # System monitoring
    pkgs.goaccess # real-time web log analyzer and interactive viewer
    pkgs.kmon # Linux kernel management and monitoring TUI
    pkgs.lnav # Log File Navigator - advanced log viewer for terminal
    pkgs.viddy # modern alternative to watch command with time-travel and diffs
    pkgs.zfxtop # system monitor with focus on process grouping and ZFX style

    # Shell enhancements
    pkgs.babashka # native Clojure scripting runtime for shell scripts
    pkgs.blesh # full-featured line editor written in pure Bash (syntax highlighting, etc.)
    pkgs.expect # tool for automating interactive applications
    pkgs.readline # GNU library for command-line editing
    pkgs.rlwrap # readline wrapper that provides editing and history for any command
  ];
}
