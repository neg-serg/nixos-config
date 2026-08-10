{
  pkgs,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.clang # C language family frontend for LLVM (wrapper script)
    pkgs.clang-tools # Standalone command line tools for C++ development
    pkgs.cmake # Cross-platform, open-source build system generator
    pkgs.cmake-format # CMake file formatter
    pkgs.ninja # Small build system with a focus on speed
    pkgs.bear # compilation database generator for clang
    pkgs.ccache # Compiler cache for fast recompilation of C/C++ code
    pkgs.gdb # GNU Project debugger
    pkgs.gcc # explicitly available in devshell
  ];
}
