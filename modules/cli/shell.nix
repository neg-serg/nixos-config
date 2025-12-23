{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.babashka # native Clojure scripting runtime
    pkgs.blesh # bluetooth shell helpers
    pkgs.expect # automate interactive TTY programs
    pkgs.fish # alternative shell
    pkgs.powershell # Microsoft pwsh shell
    pkgs.readline # readline library
    pkgs.rlwrap # readline wrapper for everything
  ];
}
