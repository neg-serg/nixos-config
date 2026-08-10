{
  pkgs,
  ...
}:
pkgs.mkShell {
  # single-purpose tools consolidated for eval efficiency
  packages = [
    pkgs.difftastic # structural diff tool
    pkgs.doggo # modern dig replacement for DNS lookups
    pkgs.rclone # rsync for cloud storage
    pkgs.numbat # scientific calculator with unit conversion
    pkgs.openconnect # Cisco AnyConnect VPN client
    pkgs.nurl # Nix URL derivation helper
    pkgs.nchat # terminal-based chat client
    pkgs.nodejs_24 # Event-driven I/O framework for the V8 JavaScript engine
    pkgs.viddy # modern watch command with history
    pkgs.uni # Unicode query tool
    pkgs.vlang # Simple, fast, safe, compiled language for developing main...
    pkgs.ape # APE file parser and emulator
    pkgs.ast-grep # AST-based structural code search
    pkgs.bespokesynth # modular software synthesizer
    pkgs.fabric-ai # AI-powered CLI workflow tool
    pkgs.stylua # Opinionated Lua code formatter
    pkgs.lnav # log file navigator with SQL queries
    pkgs.neonmodem # terminal-based LLM API client
    pkgs.netsniff-ng # high-performance network packet sniffer
    pkgs.netbird # zero-config VPN mesh network
    pkgs.mesa-demos # Mesa 3D graphics demo applications
    pkgs.speechd # speech synthesis daemon and client
    pkgs.bcc # BPF Compiler Collection tools
    pkgs.slskd # Soulseek P2P music sharing daemon
    pkgs.lldb # LLVM debugger
    pkgs.stress-ng # system stress testing tool
    pkgs.pueue # shell command queue daemon
    pkgs.gron # JSON to greppable flat format converter
    pkgs.lzbench # compression algorithm benchmark
    pkgs.vulkan-extension-layer # Vulkan extension validation layer
    pkgs.amfora # terminal Gemini protocol browser
    pkgs.freeze # render source files to images
    pkgs.hexyl # hexdump viewer
    pkgs.license-generator # CLI license boilerplates
    pkgs.plow # HTTP benchmarking tool
    pkgs.git-annex # manage files with git, without checking their contents in...
    pkgs.solfege # ear training program
    pkgs.vrrtest # validate VRR timings on Wayland
    pkgs.babashka # native Clojure scripting runtime for shell scripts
    pkgs.visidata # Terminal spreadsheet multitool for data discovery
  ];
}
