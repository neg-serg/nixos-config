{
  pkgs,
  lib,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.radare2 # UNIX-like reverse engineering framework and command-line ...
    pkgs.cutter # Free and Open Source Reverse Engineering Platform powered...
    pkgs.flawfinder # Tool to examines C/C++ source code for security flaws
    pkgs.codeql # Semantic code analysis engine
    pkgs.foremost # forensic tool
  ];
}
