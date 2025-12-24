{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.babashka # native Clojure scripting runtime for shell scripts
    pkgs.blesh # full-featured line editor written in pure Bash (syntax highlighting, etc.)
    pkgs.expect # tool for automating interactive applications
    pkgs.fish # smart and user-friendly command line shell
    pkgs.powershell # cross-platform automation and configuration tool
    pkgs.readline # GNU library for command-line editing
    pkgs.rlwrap # readline wrapper that provides editing and history for any command
  ];
}
