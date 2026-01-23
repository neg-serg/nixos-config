{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  libgit2,
  sqlite,
  openssl,
  callPackage,
}:
let
  sqlitecpp = callPackage ../sqlitecpp { };
in
stdenv.mkDerivation rec {
  pname = "bsh";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "joshikarthikey";
    repo = "bsh";
    rev = "8ea561c5729cadaabdd80e04f7e6ecbda860c135";
    hash = "sha256-ZSM60HNqADNQ2iTbvc8hsjlyqT/56328dMryVaqXEBw=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    libgit2
    sqlite
    sqlitecpp
    openssl
  ];

  cmakeFlags = [
    "-GNinja"
    "-DSQLITECPP_INTERNAL_SQLITE=ON"
    "-DSQLITE_ENABLE_FTS5=ON"
  ];

  # Patch CMakeLists.txt to use system SQLiteCpp instead of FetchContent
  postPatch = ''
    # Replace FetchContent with find_package for SQLiteCpp
    sed -i 's|include(FetchContent)|# include(FetchContent) - using system SQLiteCpp|' CMakeLists.txt
    sed -i 's|FetchContent_Declare(SQLiteCpp GIT_REPOSITORY https://github.com/SRombauts/SQLiteCpp.git GIT_TAG 3.3.1)|# FetchContent removed|' CMakeLists.txt
    sed -i 's|FetchContent_MakeAvailable(SQLiteCpp)|find_package(SQLiteCpp REQUIRED CONFIG PATHS ${sqlitecpp}/lib/cmake/SQLiteCpp)|' CMakeLists.txt

    # Change hotkey from Ctrl+F to Alt+X for toggle success filter
    sed -i "s|bindkey '^F' _bsh_toggle_success_filter|bindkey '^[x' _bsh_toggle_success_filter|" scripts/bsh_init.zsh

    # Prevent overwriting BSH_REPO_ROOT if already set (fixes NixOS path resolution)
    sed -i 's|^export BSH_REPO_ROOT=|[[ -z "$BSH_REPO_ROOT" ]] \&\& export BSH_REPO_ROOT=|' scripts/bsh_init.zsh

    # Fix SIGSEGV by moving git_libgit2_init to main after fork
    sed -i '/struct GitLib {/,/};/d' src/git_utils.cpp
    sed -i '/static GitLib git_init;/d' src/git_utils.cpp

    sed -i 's|#include "ipc.hpp"|#include "ipc.hpp"\n#include <git2.h>|' src/daemon.cpp
    sed -i 's|daemonize();|daemonize();|' src/daemon.cpp
  '';

  # Build both client and daemon
  buildPhase = ''
    runHook preBuild
    ninja bsh bsh-daemon
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m755 bsh $out/bin/bsh
    install -m755 bsh-daemon $out/bin/bsh-daemon

    # Install Zsh integration script
    mkdir -p $out/share/bsh/scripts
    install -m644 ../scripts/bsh_init.zsh $out/share/bsh/scripts/bsh_init.zsh

    runHook postInstall
  '';

  meta = with lib; {
    description = "High-Performance, Git-Aware, Predictive Terminal History Tool";
    longDescription = ''
      BSH (Better Shell History) is a robust CLI middleware designed to modernize
      the terminal experience by replacing standard flat history files with a
      structured, local SQLite database. It provides context-aware command suggestions
      based on current working directory, active Git branch, and historical success rates.
    '';
    homepage = "https://github.com/joshikarthikey/bsh";
    license = licenses.mit;
    platforms = platforms.linux ++ platforms.darwin;
    maintainers = [ ];
    mainProgram = "bsh";
  };
}
