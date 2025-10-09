{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.just # command runner for project tasks
    pkgs.bacon # background rust code checker
    pkgs.bpftrace # add tool to trace events via bpf
    pkgs.cutter # Free and Open Source Reverse Engineering Platform powered by rizin
    pkgs.ddrescue # data recovery tool
    pkgs.evcxr # rust repl
    pkgs.foremost # files extact from structure
    pkgs.freeze # generate images of code
    pkgs.gcc # gnu compiler collection
    pkgs.gdb # gnu debugger
    pkgs.hexyl # command-line hex editor
    pkgs.hyperfine # command-line benchmarking tool
    pkgs.imhex # gui hex editor
    pkgs.license-generator # cli tool for generating license files
    pkgs.lzbench # compression benchmark
    pkgs.pkgconf # package compiler and linker metadata toolkit (wrapper script)
    pkgs.plow # high performance http benchmarking tool
    pkgs.radare2 # free disassembler
    pkgs.strace # trace system-calls
  ];
}
