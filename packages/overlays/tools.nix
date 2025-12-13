inputs: _final: prev: let
  packagesRoot = inputs.self + "/packages";
  callPkg = path: extraArgs: let
    f = import path;
    wantsInputs = builtins.hasAttr "inputs" (builtins.functionArgs f);
    autoArgs =
      if wantsInputs
      then {inherit inputs;}
      else {};
  in
    prev.callPackage path (autoArgs // extraArgs);
in {
  neg = rec {
    # eBPF/BCC tools
    bpf_host_latency = callPkg (packagesRoot + "/bpf-host-latency") {};
    "bpf-host-latency" = bpf_host_latency;
    skbtrace = callPkg (packagesRoot + "/skbtrace") {};
    # CLI/util packages
    adguardian_term = callPkg (packagesRoot + "/adguardian-term") {};
    "adguardian-term" = adguardian_term;
    a2ln = callPkg (packagesRoot + "/a2ln") {};

    bt_migrate = callPkg (packagesRoot + "/bt-migrate") {};
    "bt-migrate" = bt_migrate;
    cxxmatrix = callPkg (packagesRoot + "/cxxmatrix") {};
    comma = callPkg (packagesRoot + "/comma") {};
    richcolors = callPkg (packagesRoot + "/richcolors") {};
    ls_iommu = callPkg (packagesRoot + "/ls-iommu") {};
    transmission_exporter = callPkg (packagesRoot + "/transmission-exporter") {};
    "transmission-exporter" = transmission_exporter;
    hxtools = callPkg (packagesRoot + "/hxtools") {};
    tewi = callPkg (packagesRoot + "/tewi") {};
    two_percent = callPkg (packagesRoot + "/two_percent") {};
    "two-percent" = two_percent;

    antigravity = callPkg (packagesRoot + "/antigravity") {};
    nemu = callPkg (packagesRoot + "/nemu") {};
    _nemu = nemu;

    # Music album metadata CLI (used by music-rename script)
    albumdetails = prev.stdenv.mkDerivation rec {
      pname = "albumdetails";
      version = "0.1";

      src = prev.fetchFromGitHub {
        owner = "neg-serg";
        repo = "albumdetails";
        rev = "91f4a546ccb42d82ae3b97462da73c284f05dbbe";
        hash = "sha256-9iaSyNqc/hXKc4iiDB6C7+2CMvKLWCRycsv6qVBD4wk=";
      };

      buildInputs = [prev.taglib];

      # Provide TagLib headers/libs to Makefile's LDLIBS
      preBuild = ''
        makeFlagsArray+=(LDLIBS="-I${prev.taglib}/include/taglib -L${prev.taglib}/lib -ltag_c")
      '';

      # Upstream Makefile supports PREFIX+DESTDIR, but copying is simpler here
      installPhase = ''
        mkdir -p "$out/bin"
        install -m755 albumdetails "$out/bin/albumdetails"
      '';

      meta = with prev.lib; {
        description = "Generate details for music album";
        homepage = "https://github.com/neg-serg/albumdetails";
        license = licenses.mit;
        platforms = platforms.unix;
        mainProgram = "albumdetails";
      };
    };

    # Pretty-printer library + CLI (ppinfo)
    pretty_printer = callPkg (packagesRoot + "/pretty-printer") {};
    "pretty-printer" = pretty_printer;

    # Rofi plugins / desktop helpers
    rofi_games = callPkg (packagesRoot + "/rofi-games") {};
    "rofi-games" = rofi_games;

    # Trader Workstation (IBKR) packaged from upstream installer
    tws = callPkg (packagesRoot + "/tws") {};

    # duf fork with --style plain, --no-header, --no-bars flags
    duf = callPkg (packagesRoot + "/duf") {};

    # ncpamixer with custom config
    ncpamixer-wrapped = let
      ncpaConfig =
        prev.writeText "ncpamixer.conf"
        (builtins.readFile (inputs.self + "/home/modules/media/audio/ncpamixer.conf"));
    in
      prev.symlinkJoin {
        name = "ncpamixer-wrapped";
        paths = [prev.ncpamixer];
        buildInputs = [prev.makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/ncpamixer \
            --add-flags "-c ${ncpaConfig}"
        '';
      };

    # nextcloud-client with GPU disabled (for stability)
    nextcloud-wrapped = prev.symlinkJoin {
      name = "nextcloud-wrapped";
      paths = [prev.nextcloud-client];
      buildInputs = [prev.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/nextcloud \
          --add-flags "--disable-gpu --disable-software-rasterizer" \
          --set QTWEBENGINE_DISABLE_GPU "1" \
          --set QTWEBENGINE_CHROMIUM_FLAGS "--disable-gpu --disable-software-rasterizer"
      '';
    };
  };
}
