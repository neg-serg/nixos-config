{ pkgs, ... }: {
  nativeBuildInputs = [
    pkgs.clang # C language family frontend for LLVM (wrapper script)
    pkgs.clang-tools # clangd + clang-format (moved out of the system closure)
    pkgs.lldb # lldb + lldb-dap (nvim-dap / dsh-debug)
    pkgs.cmake # Cross-platform, open-source build system generator
    pkgs.cmake-language-server # CMake LSP (nvim-lspconfig 'cmake')
    pkgs.cmake-format # CMake file formatter
    pkgs.ninja # Small build system with a focus on speed
    pkgs.bear # compilation database generator for clang
    pkgs.ccache # Compiler cache for fast recompilation of C/C++ code
    pkgs.gdb # GNU Project debugger
    pkgs.gcc # explicitly available in devshell
  ];
}
