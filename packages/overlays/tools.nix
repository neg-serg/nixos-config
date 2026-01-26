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
    # Surfingkeys configuration
    surfingkeys_conf = callPkg (packagesRoot + "/surfingkeys-conf") { };
    "surfingkeys-conf" = surfingkeys_conf;

    # Zsh Fancy Completions
    zsh-fancy-completions = callPkg (packagesRoot + "/zsh-fancy-completions") { };

    rsmetrx = inputs.rsmetrx.packages.${prev.stdenv.hostPlatform.system}.default;

    # Music album metadata CLI (used by music-rename script)
    albumdetails = callPkg (packagesRoot + "/albumdetails") { };

    # Pretty-printer library + CLI (ppinfo)
    pretty_printer = callPkg (packagesRoot + "/pretty-printer") { };
    "pretty-printer" = pretty_printer;

    # Better Shell History - Git-aware predictive terminal history tool

    # Trader Workstation (IBKR) packaged from upstream installer

    # duf fork with --style plain, --no-header, --no-bars flags
    duf = callPkg (packagesRoot + "/duf") { };

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
