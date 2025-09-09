{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    just # command runner for project tasks
    bacon # background rust code checker
    bpftrace # add tool to trace events via bpf
    cutter # Free and Open Source Reverse Engineering Platform powered by rizin
    ddrescue # data recovery tool
    evcxr # rust repl
    foremost # files extact from structure
    freeze # generate images of code
    gcc # gnu compiler collection
    gdb # gnu debugger
    hexyl # command-line hex editor
    hyperfine # command-line benchmarking tool
    imhex # gui hex editor
    license-generator # cli tool for generating license files
    ltrace # trace functions
    lzbench # compression benchmark
    pkgconf # package compiler and linker metadata toolkit (wrapper script)
    plow # high performance http benchmarking tool
    radare2 # free disassembler
    strace # trace system-calls
  ];
}
