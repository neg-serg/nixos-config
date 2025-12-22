{
  description = "Nix shell for Tarantool";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (import ../../overlays/default.nix)
        ];
      };
    in {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.gdb
          pkgs.cpulimit
          pkgs.netcat-openbsd

          # tt
          pkgs.lua51Packages.lua
          pkgs.lua51Packages.luacheck
          pkgs.lua51Packages.luacov
          pkgs.lua51Packages.luacheck
          pkgs.unzip
          pkgs.pkg-config

          pkgs.cpulimit

          # Tarantool dependencies
          pkgs.curl
          pkgs.bc
          pkgs.libyaml

          pkgs.git
          pkgs.gcc
          # clang
          pkgs.c-ares
          pkgs.gnumake
          pkgs.cmake
          pkgs.nghttp2
          pkgs.autoconf
          pkgs.automake
          pkgs.libtool
          pkgs.readline
          pkgs.ncurses
          pkgs.openssl
          pkgs.icu
          pkgs.zlib
          pkgs.python310
          pkgs.python310Packages.pip #pyyaml, gevent, six
          pkgs.lz4

          # TT building
          pkgs.go
          pkgs.mage
          pkgs.unzip

          # Cartridge
          pkgs.nodejs

          # Tcpdump
          pkgs.libnl
          pkgs.libpcap
          pkgs._msgpuck
        ];
        shellHook = ''
          export LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib
          export MSGPUCK_INCLUDE_DIR=${pkgs._msgpuck}/include
          export MSGPUCK_LIBRARY=${pkgs._msgpuck}/lib/libmsgpuck.a
          export LUA_INCDIR=${pkgs.lua51Packages.lua}/include
          export TARANTOOL_DIR=$HOME/Programming/tnt/tarantool/install/var/empty/local
          export TARANTOOL_INCDIR=$TARANTOOL_DIR/include
          export PATH=$TARANTOOL_DIR/bin:$PATH
          # Cluster management
          export PATH=$HOME/Programming/tnt/tarantool/test-run:$PATH
          export PATH=$HOME/Programming/tnt/tt:$PATH
          export PATH=$HOME/Programming/tnt/tt-ee:$PATH
          # Lint check
          export PATH=$HOME/Programming/tnt/checkpatch:$PATH
          export PATH=$HOME/Programming/tnt/cartridge-cli:$PATH
          # Use gcc for compilation
          export CC=${pkgs.gcc}/bin/gcc
          export CXX=${pkgs.gcc}/bin/c++
          # export CC=${pkgs.clang}/bin/clang
          # export CXX=${pkgs.clang}/bin/clang++
          source $HOME/Programming/tnt/.venv/bin/activate
          # Activate ssh.
          eval `ssh-agent -s`
          # ssh-add ~/.ssh/work
        '';

        # See https://github.com/NixOS/nixpkgs/issues/18995
        hardeningDisable = ["fortify"];
      };
    });
}
