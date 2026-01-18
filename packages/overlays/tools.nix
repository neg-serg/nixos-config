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
  neg = rec {
    # Surfingkeys configuration
    surfingkeys_conf = callPkg (packagesRoot + "/surfingkeys-conf") { };
    "surfingkeys-conf" = surfingkeys_conf;

    two_percent = callPkg (packagesRoot + "/two_percent") { };
    "two-percent" = two_percent;

    rsmetrx = inputs.rsmetrx.packages.${prev.stdenv.hostPlatform.system}.default;

    # Music album metadata CLI (used by music-rename script)
    albumdetails = callPkg (packagesRoot + "/albumdetails") { };

    # Pretty-printer library + CLI (ppinfo)
    pretty_printer = callPkg (packagesRoot + "/pretty-printer") { };
    "pretty-printer" = pretty_printer;

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
