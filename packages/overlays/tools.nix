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
  # warpd: nixpkgs 26.05 src hash is stale for v1.3.5 (upstream tag tarball
  # changed) — re-pin to the actual fetched content.
  warpd = prev.warpd.overrideAttrs (_: {
    src = prev.fetchFromGitHub {
      owner = "rvaiya";
      repo = "warpd";
      rev = "v1.3.5";
      hash = "sha256-mXnw+7M4avvHizQt6rq8hX7FfhlNrrrLvndkmSpElA8=";
      leaveDotGit = true;
    };
  });

  neg = (prev.neg or { }) // rec {
    albumdetails = callPkg (packagesRoot + "/albumdetails") { }; # Music album metadata CLI (used by music-rename script)
    brrtfetch = callPkg (packagesRoot + "/brrtfetch") { }; # Animated ASCII art GIF renderer alongside sysinfo output
    duf = callPkg (packagesRoot + "/duf") { }; # duf fork with --style plain, --no-header, --no-bars flags
    hwctl = callPkg (packagesRoot + "/hwctl") { }; # Hardware control CLI — CPU boost, V-Cache masks, Nuvoton fan control
    omp = callPkg (packagesRoot + "/omp") { }; # Oh My Pi (omp) — AI coding agent with LSP, DAP, subagents
    hypr-focus = callPkg (packagesRoot + "/hypr-focus") { }; # Rust-based window focus CLI — set window class on focused Hyprland window
    pretty_printer = callPkg (packagesRoot + "/pretty-printer") { }; # Pretty-printer library + CLI (ppinfo)
    rsmetrx = inputs.rsmetrx.packages.${prev.stdenv.hostPlatform.system}.default;
    talktype = callPkg (packagesRoot + "/talktype") { }; # Push-to-talk voice typing tool (F9 to record, transcribe, paste)
    termeverything = callPkg (packagesRoot + "/termeverything") { }; # Run GUI windows inside your terminal (Wayland compositor → ANSI)
    zsh-native-syntax = callPkg (packagesRoot + "/zsh-native-syntax") { }; # Native Rust-based zsh syntax highlighting engine

    "pretty-printer" = pretty_printer;

    # ncpamixer-wrapped removed — nix-maid manages config via ~/.config/ncpamixer.conf
  };
}
