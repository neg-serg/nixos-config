{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.entr # run commands on file change
    pkgs.inotify-tools # shell inotify bindings
    pkgs.lsof # list open files
    pkgs.parallel # parallel xargs
    pkgs.procps # /proc tools
    pkgs.progress # show progress for coreutils
    pkgs.psmisc # killall and friends
    pkgs.pueue # queue manager
    pkgs.pv # pipe viewer
    pkgs.reptyr # move app to another pty
  ];
}
