inputs: _final: prev:
let
  packagesRoot = inputs.self + "/packages";
  callPkg =
    path: extraArgs:
    let
      f = import path;
      wantsInputs = builtins.hasAttr "inputs" (builtins.functionArgs f);
      autoArgs = if wantsInputs then { inherit inputs; } else { };
    in
    prev.callPackage path (autoArgs // extraArgs);
in
{
  neg = (prev.neg or { }) // rec {
    albumdetails = callPkg (packagesRoot + "/albumdetails") { }; # Music album metadata CLI (used by music-rename script)
    brrtfetch = callPkg (packagesRoot + "/brrtfetch") { }; # Animated ASCII art GIF renderer alongside sysinfo output
    duf = callPkg (packagesRoot + "/duf") { }; # duf fork with --style plain, --no-header, --no-bars flags
    hwctl = callPkg (packagesRoot + "/hwctl") { }; # Hardware control CLI — CPU boost, V-Cache masks, Nuvoton fan control
    inferno = callPkg (packagesRoot + "/inferno") { }; # Rust port of the FlameGraph performance profiling tool suite (flamegraph + collapse scripts)
    hypr-focus = callPkg (packagesRoot + "/hypr-focus") { }; # Rust-based window focus CLI — set window class on focused Hyprland window
    openagentscontrol = callPkg (packagesRoot + "/openagentscontrol") { }; # OpenAgentsControl — AI agent framework for plan-first development (agents + contexts for OpenCode)
    palettum = callPkg (packagesRoot + "/palettum") { }; # Image/GIF/video recolor tool with custom palettes
    pretty_printer = callPkg (packagesRoot + "/pretty-printer") { }; # Pretty-printer library + CLI (ppinfo)
    proteinview = callPkg (packagesRoot + "/proteinview") { }; # Terminal protein structure viewer — interactive 3D visualization of PDB/mmCIF
    rsmetrx = inputs.rsmetrx.packages.${prev.stdenv.hostPlatform.system}.default;
    solarust = callPkg (packagesRoot + "/solarust") { }; # Random solar system simulator for the terminal
    sqlit = callPkg (packagesRoot + "/sqlit") { }; # A terminal UI for SQL databases
    surfingkeys_conf = callPkg (packagesRoot + "/surfingkeys-conf") { }; # Surfingkeys configuration    
    talktype = callPkg (packagesRoot + "/talktype") { }; # Push-to-talk voice typing tool (F9 to record, transcribe, paste)
    termeverything = callPkg (packagesRoot + "/termeverything") { }; # Run GUI windows inside your terminal (Wayland compositor → ANSI)
    zsh-native-syntax = callPkg (packagesRoot + "/zsh-native-syntax") { }; # Native Rust-based zsh syntax highlighting engine

    "surfingkeys-conf" = surfingkeys_conf;
    "pretty-printer" = pretty_printer;

    # ncpamixer with custom config
    ncpamixer-wrapped =
      let
        ncpaConfig = prev.writeText "ncpamixer.conf" (
          builtins.readFile (inputs.self + "/files/gui/ncpamixer.conf")
        );
      in
      prev.symlinkJoin {
        name = "ncpamixer-wrapped";
        paths = [ prev.ncpamixer ];
        buildInputs = [ prev.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/ncpamixer \
            --add-flags "-c ${ncpaConfig}"
        '';
      };
  };
}
