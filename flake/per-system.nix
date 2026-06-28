{
  self,
  inputs,
  nixpkgs,
  flakeLib,
  pkgs,
  ...
}:
system:
let
  inherit (nixpkgs) lib;
  mkCustomPkgs = flakeLib.mkCustomPkgs; # pkgs is now passed from flake.nix
  nixfmtPkg = nixpkgs.legacyPackages.${system}.nixfmt;

  # Pre-commit utility per system
  preCommit = inputs.pre-commit-hooks.lib.${system}.run {
    src = self;
    hooks = {
      nixfmt-rfc-style = {
        enable = true;
        package = nixfmtPkg;
        excludes = [ "flake.nix" ];
      };
      statix.enable = false;
      deadnix.enable = true;
    };
  };
in
{
  packages = (mkCustomPkgs pkgs) // {
    default = pkgs.zsh; # default shell for flake environment
    docs-modules = import ./docs-modules.nix {
      inherit pkgs lib self;
    };
    antigravity = pkgs.antigravity-manual;
  };

  formatter = pkgs.writeShellApplication {
    name = "fmt";
    runtimeInputs = [
      nixfmtPkg # nix formatter
      pkgs.black # python formatter
      pkgs.python3Packages.mdformat # markdown formatter
      pkgs.shfmt # shell script formatter
      pkgs.treefmt # unified formatting tool
    ];
    text = ''
      set -euo pipefail
      if git rev-parse --show-toplevel >/dev/null 2>&1; then
        repo_root="$(git rev-parse --show-toplevel)"
      else
        repo_root="${self}"
      fi
      cd "$repo_root"
      tmp_conf=$(mktemp)
      trap 'rm -f "$tmp_conf"' EXIT
      cp ${../treefmt.toml} "$tmp_conf"
      exec treefmt --config-file "$tmp_conf" --tree-root "$repo_root" "$@"
    '';
  };

  checks = { };
  devShells = {
    ai = pkgs.mkShell {
      nativeBuildInputs = [
        (pkgs.ai-studio or pkgs.lmstudio) # LM Studio is an easy to use desktop app for experimenting...
        pkgs.aichat
        pkgs.aider-chat
        pkgs.openai # Python client library for the OpenAI API
        pkgs.code-cursor-fhs # AI code editor (VS Code)
      ];
    };

    default = pkgs.mkShell {
      inherit (preCommit) shellHook;
      packages = [
        pkgs.valgrind # Tool for debugging and profiling
        nixfmtPkg # nix formatter
        pkgs.deadnix # unused code detector
        pkgs.statix # nix antipattern linter
        pkgs.nil # nix language server
        pkgs.just # command runner
        pkgs.jq # json processor
        # Linters/Formatters required by 'just lint' (moved from system pkgs)
        pkgs.black
        pkgs.ruff # Extremely fast Python linter and code formatter
        pkgs.mypy # Optional static typing for Python
        pkgs.stylua # Opinionated Lua code formatter
      ];
    };

    difftastic = pkgs.mkShell {
      packages = [ pkgs.difftastic ];
    };

    doggo = pkgs.mkShell {
      packages = [ pkgs.doggo ];
    };

    rclone = pkgs.mkShell {
      packages = [ pkgs.rclone ];
    };

    helix = pkgs.mkShell {
      packages = [ pkgs.helix ];
      shellHook = ''
        alias hx="XDG_CONFIG_HOME=$PWD/files helix"
      '';
    };

    haskell =
      let
        tidalGhci = pkgs.writeShellScriptBin "tidal-ghci" ''
          exec ${pkgs.ghc.withPackages (ps: [ ps.tidal ])}/bin/ghci "$@" # Glasgow Haskell Compiler
        '';
        optionalHaskellTools =
          lib.optionals (pkgs ? fourmolu) [ pkgs.fourmolu ] # haskell formatter
          ++ lib.optionals (pkgs ? hindent) [ pkgs.hindent ]; # alternative haskell formatter
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.ghc # compiler
          pkgs.cabal-install # package/build tool
          pkgs.stack # alternative build tool
          pkgs.haskell-language-server # IDE/LSP backend
          pkgs.hlint # linter
          pkgs.ormolu # formatter
          pkgs.ghcid # fast GHCi reload loop
          tidalGhci # TidalCycles GHCi wrapper
          pkgs.haskellPackages.tidal # TidalCycles library
        ]
        ++ optionalHaskellTools;
      };

    rust =
      let
        optionalRustDebugAdapters = lib.optionals (pkgs ? codelldb) [
          pkgs.codelldb # LLDB-based debug adapter for Rust (DAP)
        ];
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.rustup # manage Rust channels/components
          pkgs.graphviz # dot backend for rustaceanvim crateGraph
          pkgs.bacon # background rust code checker
          pkgs.evcxr # Rust REPL
        ]
        ++ optionalRustDebugAdapters;
      };
    cpp = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.clang # C language family frontend for LLVM (wrapper script)
        pkgs.clang-tools # Standalone command line tools for C++ development
        pkgs.cmake # Cross-platform, open-source build system generator
        pkgs.cmake-format # CMake file formatter
        pkgs.ninja # Small build system with a focus on speed
        pkgs.bear
        pkgs.ccache # Compiler cache for fast recompilation of C/C++ code
        pkgs.gdb # GNU Project debugger
        pkgs.gcc # explicitly available in devshell
      ];
    };

    java = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.jdk # Open-source Java Development Kit
        pkgs.gradle # Enterprise-grade build system
      ];
    };

    node = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.nodejs_24 # Event-driven I/O framework for the V8 JavaScript engine
      ];
    };

    numbat = pkgs.mkShell {
      packages = [ pkgs.numbat ];
    };

    openconnect = pkgs.mkShell {
      packages = [ pkgs.openconnect ];
    };

    nurl = pkgs.mkShell {
      packages = [ pkgs.nurl ];
    };

    nchat = pkgs.mkShell {
      packages = [ pkgs.nchat ];
    };

    vlang = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.vlang # Simple, fast, safe, compiled language for developing main...
      ];
    };

    viddy = pkgs.mkShell {
      packages = [ pkgs.viddy ];
    };

    uni = pkgs.mkShell {
      packages = [ pkgs.uni ];
    };

    re = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.radare2 # UNIX-like reverse engineering framework and command-line ...
        pkgs.cutter # Free and Open Source Reverse Engineering Platform powered...
        pkgs.flawfinder # Tool to examines C/C++ source code for security flaws
        pkgs.codeql # Semantic code analysis engine
        pkgs.foremost # forensic tool
      ];
    };

    infra =
      let
        optionalIaCTools = lib.optionals (pkgs ? aiac) [ pkgs.aiac ];
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.ansible
          pkgs.terraform # Tool for building, changing, and versioning infrastructure
          pkgs.opentofu # Tool for building, changing, and versioning infrastructure
        ]
        ++ optionalIaCTools;
      };

    python =
      let
        # Replicating logic from modules/dev/python/pkgs.nix
        myPythonPackages =
          ps: with ps; [
            # Core
            annoy
            beautifulsoup4
            colored
            docopt
            fonttools
            mutagen
            numpy
            orjson
            pillow
            psutil
            requests
            tabulate
            # Tools
            dbus-python
            fontforge

            pynvim
          ];
        pythonEnv = pkgs.python3-lto.withPackages myPythonPackages;
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          pythonEnv
          pkgs.pipx # Install and run Python applications in isolated environments
          pkgs.black
          pkgs.ruff # Extremely fast Python linter and code formatter
          pkgs.mypy # Optional static typing for Python
        ];
      };

    lua = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.stylua # Opinionated Lua code formatter
      ];
    };

    android = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.android-tools
        pkgs.scrcpy # Display and control Android devices over USB or TCP/IP
        pkgs.adbfs-rootless
        pkgs.adbtuifm
      ]
      ++ lib.optionals (pkgs ? fuse3) [ pkgs.fuse3 ]; # Library that allows filesystems to be implemented in user...
    };

    ape = pkgs.mkShell {
      packages = [ pkgs.ape ];
    };

    "ast-grep" = pkgs.mkShell {
      packages = [ pkgs.ast-grep ];
    };

    bespokesynth = pkgs.mkShell {
      packages = [ pkgs.bespokesynth ];
    };

    fabric-ai = pkgs.mkShell {
      packages = [ pkgs.fabric-ai ];
    };

    qmk = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.qmk # Program to help users work with QMK Firmware
        pkgs.qmk_hid # Commandline tool for interactng with QMK devices over HID
        pkgs.keymapviz # Qmk keymap.c visualizer
      ];
    };

    radicle = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.radicle-node # Radicle node and CLI for decentralized code collaboration
        pkgs.radicle-explorer # Web frontend for Radicle
      ];
    };

    pentest = pkgs.mkShell {
      nativeBuildInputs = [
        # Recon
        pkgs.masscan # Fast scan of the Internet
        pkgs.rustscan # Faster Nmap Scanning with Rust
        pkgs.zmap # Fast single packet network scanner designed for Internet-...
        pkgs.dnsenum # Tool to enumerate DNS information
        pkgs.dnsrecon # DNS Enumeration script
        pkgs.dnstracer # Determines where a given Domain Name Server (DNS) gets it...
        pkgs.fierce # DNS reconnaissance tool for locating non-contiguous IP space
        pkgs.netdiscover # Network address discovering tool, developed mainly for th...
        pkgs.enum4linux # Tool for enumerating information from Windows and Samba s...
        pkgs.onesixtyone # Fast SNMP Scanner
        pkgs.arping
        pkgs.cloudbrute # Cloud enumeration tool
        pkgs.sn0int # Semi-automatic OSINT framework and package manager
        pkgs.netmask # IP address formatting tool
        pkgs.net-snmp # Clients and server for the SNMP network monitoring protocol
        pkgs.sslsplit # Transparent SSL/TLS interception
        pkgs.ssldump # SSLv3/TLS network protocol analyzer
        pkgs.sslh # Applicative Protocol Multiplexer (e.g. share SSH and HTTP...
        pkgs.sslscan # Tests SSL/TLS services and discover supported cipher suites
        pkgs.swaks # Featureful, flexible, scriptable, transaction-oriented SM...

        # Web
        pkgs.gobuster # Tool used to brute-force URIs, DNS subdomains, Virtual Ho...
        pkgs.dirb # Web content scanner
        pkgs.wfuzz # Web content fuzzer to facilitate web applications assessm...
        pkgs.zap # Java application for web penetration testing
        pkgs.katana # Next-generation crawling and spidering framework
        pkgs.urlhunter # Recon tool that allows searching shortened URLs

        # Passwords
        pkgs.john # John the Ripper password cracker
        pkgs.hashcat # Fast password cracker
        pkgs.thc-hydra # Very fast network logon cracker which support many differ...
        pkgs.brutespray
        pkgs.crowbar # Brute forcing tool that can be used during penetration tests
        pkgs.crunch # Wordlist generator
        pkgs.chntpw # Utility to reset the password of any user that has a vali...
        pkgs.hcxtools # Tools for capturing wlan traffic and conversion to hashca...
        pkgs.phrasendrescher # Modular and multi processing pass phrase cracking tool

        # Exploitation
        pkgs.metasploit # Metasploit Framework - a collection of exploits
        pkgs.exploitdb # Archive of public exploits and corresponding vulnerable s...
        pkgs.msfpc # MSFvenom Payload Creator
        pkgs.shellnoob # Shellcode writing toolkit
        pkgs.termineter # Smart Meter Security Testing Framework

        # Sniffing/MITM
        pkgs.wireshark # Powerful network protocol analyzer
        pkgs.tshark # Powerful network protocol analyzer
        pkgs.termshark # Terminal UI for wireshark-cli, inspired by Wireshark
        pkgs.tcpdump # Network sniffer
        pkgs.bettercap
        pkgs.mitmproxy # Man-in-the-middle proxy
        pkgs.dsniff # Collection of tools for network auditing and penetration ...
        pkgs.rshijack # TCP connection hijacker
        pkgs.sipp # SIPp testing tool
        pkgs.sniffglue # Secure multithreaded packet sniffer

        # Forensics
        pkgs.sleuthkit # Forensic/data recovery tool
        pkgs.volatility3 # Volatile memory extraction frameworks
        pkgs.ddrescue # GNU ddrescue, a data recovery tool
        pkgs.ext4magic # Recover / undelete files from ext3 or ext4 partitions
        pkgs.extundelete # Utility that can recover deleted files from an ext3 or ex...
        pkgs.steghide # Open source steganography program
        pkgs.stegseek # Tool to crack steganography
        pkgs.outguess # Universal steganographic tool that allows the insertion o...
        pkgs.zsteg # Detect stegano-hidden data in PNG & BMP
        pkgs.stegsolve # Steganographic image analyzer, solver and data extractor ...
        pkgs.ghidra-bin # Software reverse engineering (SRE) suite of tools develop...
        pkgs.capstone
        pkgs.pdf-parser # Parse a PDF document
        pkgs.p0f # Passive network reconnaissance and fingerprinting tool

        # Wireless
        pkgs.aircrack-ng
        pkgs.impala # TUI for managing wifi

        # Misc Network
        pkgs.hping # Command-line oriented TCP/IP packet assembler/analyzer
        pkgs.fping # Send ICMP echo probes to network hosts
        pkgs.tcptraceroute # Traceroute implementation using TCP packets
        pkgs.trippy # Network diagnostic tool
      ];
    };

    elf = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.patchelf # Small utility to modify the dynamic linker and RPATH of E...
        pkgs.elfutils # Set of utilities to handle ELF objects
        pkgs.chrpath # Command line tool to adjust the RPATH or RUNPATH of ELF b...
        pkgs.debugedit # Provides programs and scripts for creating debuginfo and ...
        pkgs.dump_syms # Command-line utility for parsing the debugging informatio...
      ];
    };

    gitops = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.git-annex # manage files with git, without checking their contents in...
      ];
    };

    graphics = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.librsvg # Small library to render SVG images to Cairo surfaces
        pkgs.libxml2 # XML parsing library for C
      ];
    };

    latex = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.rubber # Wrapper for LaTeX and friends
        (pkgs.texlive.combined.scheme-full.withPackages (ps: [
          ps.cyrillic
          ps.cyrillic-bin
          ps.collection-langcyrillic
          ps.context-cyrillicnumbers
        ]))
        pkgs.sioyek # PDF viewer designed for research papers and technical books
      ];
    };

    lnav = pkgs.mkShell {
      packages = [ pkgs.lnav ];
    };

    music-learning = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.solfege # ear training program
      ];
    };

    neonmodem = pkgs.mkShell {
      packages = [ pkgs.neonmodem ];
    };

    "netsniff-ng" = pkgs.mkShell {
      packages = [ pkgs.netsniff-ng ];
    };

    netbird = pkgs.mkShell {
      packages = [ pkgs.netbird ];
    };

    misc = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.xephem # astronomy application
        pkgs.xlife # cellular automata explorer
        pkgs.free42 # HP-42S calculator clone
        pkgs.cool-retro-term # retro CRT terminal emulator
        pkgs.almonds # TUI fractal viewer
      ];
    };

    media = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.ffmpeg-full # complete multimedia framework
        pkgs.gmic # image processing framework
      ];
    };

    "mesa-demos" = pkgs.mkShell {
      packages = [ pkgs.mesa-demos ];
    };

    virt = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.guestfs-tools # tools for accessing and modifying virtual machine disk images
        pkgs.lima # Linux virtual machines
        pkgs.quickemu # quickly create and run highly optimised desktop virtual machines
      ];
    };
    text = pkgs.mkShell {
      # light text processing and previewing tools
      nativeBuildInputs = [
        pkgs.recoll # metadata-based full-text desktop search tool
        pkgs.tesseract # OCR engine with multi-language support
      ];
    };

    vrr = pkgs.mkShell {
      # tools for VRR (Variable Refresh Rate) testing
      nativeBuildInputs = [
        pkgs.vrrtest # validate VRR timings on Wayland
      ];
    };

    clojure = pkgs.mkShell {
      # Clojure development and scripting environment
      nativeBuildInputs = [
        pkgs.babashka # native Clojure scripting runtime for shell scripts
      ];
    };

    "pro-audio" = pkgs.mkShell {
      # professional audio production environment (DAWs, editors, synths)
      nativeBuildInputs = [
        pkgs.reaper # Digital Audio Workstation
        pkgs.glicol-cli # audio DSL for generative compositions
        pkgs.ocenaudio # lightweight waveform editor
        pkgs.vital # spectral wavetable synth
        pkgs.dexed # DX7-compatible synth
        pkgs.stochas # probability-driven MIDI sequencer
        pkgs.vcv-rack # modular synth platform
      ];
    };

    visidata = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.visidata # Terminal spreadsheet multitool for data discovery
      ];
    };

    "web-archive" = pkgs.mkShell {
      packages = [
        pkgs.gallery-dl # download image galleries
        pkgs.monolith # single-file webpage archiver
      ];
    };

    speech = pkgs.mkShell {
      packages = [ pkgs.speechd ];
    };

    bcc = pkgs.mkShell {
      packages = [ pkgs.bcc ];
    };

    slskd = pkgs.mkShell {
      packages = [ pkgs.slskd ];
    };

    db = pkgs.mkShell {
      packages = [
        pkgs.iredis # Redis enhanced CLI
        pkgs.pgcli # PostgreSQL TUI client
        pkgs.sqlite # self-contained, serverless SQL DB
      ];
    };

    lldb = pkgs.mkShell {
      packages = [ pkgs.lldb ]; # LLVM debugger
    };

    k8s = pkgs.mkShell {
      packages = [
        pkgs.kubectl # Kubernetes CLI
        pkgs.kubectx # fast switch Kubernetes contexts
        pkgs.kubernetes-helm # Helm package manager
        pkgs.scaleway-cli # Scaleway cloud CLI
        pkgs.kubecolor # Colorize kubectl output
      ];
    };

    ranger = pkgs.mkShell {
      packages = [ pkgs.ranger ];
    };

    "stress-ng" = pkgs.mkShell {
      packages = [ pkgs.stress-ng ];
    };

    pueue = pkgs.mkShell {
      packages = [ pkgs.pueue ];
    };

    gron = pkgs.mkShell {
      packages = [ pkgs.gron ];
    };

    lzbench = pkgs.mkShell {
      packages = [ pkgs.lzbench ];
    };

    btrfs = pkgs.mkShell {
      packages = [ pkgs.btrfs-progs ];
    };

    vulkan = pkgs.mkShell {
      packages = [ pkgs.vulkan-extension-layer ];
    };

    amfora = pkgs.mkShell {
      packages = [ pkgs.amfora ];
    };

    freeze = pkgs.mkShell {
      packages = [ pkgs.freeze ]; # render source files to images
    };

    hexyl = pkgs.mkShell {
      packages = [ pkgs.hexyl ]; # hexdump viewer
    };

    license = pkgs.mkShell {
      packages = [ pkgs.license-generator ]; # CLI license boilerplates
    };

    plow = pkgs.mkShell {
      packages = [ pkgs.plow ]; # HTTP benchmarking tool
    };

    wine = pkgs.mkShell {
      packages = [
        pkgs.dxvk # setup script for DXVK
        pkgs.vkd3d # DX12 for Wine
        pkgs.wineWow64Packages.staging # Wine (staging) for Windows apps
        pkgs.winetricks # helpers for Wine (e.g., DXVK)
        pkgs.wineWow64Packages.full # full 32/64-bit Wine
      ];
    };
  };

  apps =
    let
      genOptions = pkgs.writeShellApplication {
        name = "gen-options";
        runtimeInputs = [
          pkgs.git # version control
          pkgs.jq # json processor
          pkgs.nix # nix package manager
        ];
        text = ''
          set -euo pipefail
          exec "${self}/scripts/dev/gen-options.sh" "$@"
        '';
      };
      fmtApp = pkgs.writeShellApplication {
        name = "fmt";
        runtimeInputs = [
          nixfmtPkg
          pkgs.black
          pkgs.python3Packages.mdformat
          pkgs.shfmt # Shell parser and formatter
          pkgs.treefmt # One CLI to format the code tree
        ];
        text = ''
          set -euo pipefail
          if git rev-parse --show-toplevel >/dev/null 2>&1; then
            repo_root="$(git rev-parse --show-toplevel)"
          else
            repo_root="${self}"
          fi
          cd "$repo_root"
          tmp_conf=$(mktemp)
          trap 'rm -f "$tmp_conf"' EXIT
          cp ${../treefmt.toml} "$tmp_conf"
          exec treefmt --config-file "$tmp_conf" --tree-root "$repo_root" "$@"
        '';
      };
    in
    {
      gen-options = {
        type = "app";
        program = "${genOptions}/bin/gen-options";
      };
      fmt = {
        type = "app";
        program = "${fmtApp}/bin/fmt";
      };
    };
}
