{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.net.vpn-scripts;
  scriptDir = ./scripts;
  libDir = ./lib;

  scripts = {
    "cdn-proxy" = "cdn-proxy.py";
    "cdn-forward" = "cdn-forward.sh";
    "socks5-forward" = "socks5-forward.py";
    "check-vpn-status" = "check-vpn-status.sh";
    "manual-tun-routes" = "manual-tun-routes.sh";
    "vpn-split-router" = "vpn_split_router.py";
    "amnezia-import-tun-config" = "amnezia-import-tun-config.sh";
    "enable-vpn-hybrid" = "enable-vpn-hybrid.sh";
    "start-hybrid-vpn" = "start-hybrid-vpn.sh";
    "test-browser-vpn" = "test-browser-vpn.sh";
  };

  scriptsSourcingPrettySh = [
    "check-vpn-status"
    "start-hybrid-vpn"
    "test-browser-vpn"
  ];

  scriptsNeedingPyYaml = [
    "vpn-split-router"
  ];

  vpnScriptsPkg = pkgs.stdenv.mkDerivation {
    name = "vpn-scripts";

    buildInputs = with pkgs; [
      python3
      makeWrapper
    ];

    dontUnpack = true;

    installPhase =
      let
        installScripts = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (binName: fileName: ''
            install -D -m755 ${scriptDir + "/${fileName}"} "$out/share/vpn-scripts/${fileName}"
            patchShebangs "$out/share/vpn-scripts/${fileName}"
            ln -sf "../share/vpn-scripts/${fileName}" "$out/bin/${binName}"
          '') scripts
        );
        fixPrettyShSources = lib.concatStringsSep "\n" (
          map (name: ''
            substituteInPlace "$out/share/vpn-scripts/${scripts.${name}}" \
              --replace-fail 'source "''${SCRIPT_DIR}/lib/pretty.sh"' \
                             'source "$out/share/vpn-scripts/lib/pretty.sh"'
          '') scriptsSourcingPrettySh
        );
        wrapPyYamlScripts = lib.concatStringsSep "\n" (
          map (name: ''
            wrapProgram "$out/bin/${name}" \
              --prefix PYTHONPATH : "${pkgs.python3Packages.pyyaml}/${pkgs.python3.sitePackages}" \
              --prefix PYTHONPATH : "$out/share/vpn-scripts/lib"
          '') scriptsNeedingPyYaml
        );
      in
      ''
        mkdir -p "$out/bin" "$out/share/vpn-scripts/lib"

        install -m644 ${libDir + "/pretty.sh"} "$out/share/vpn-scripts/lib/pretty.sh"
        install -m644 ${libDir + "/pretty.py"} "$out/share/vpn-scripts/lib/pretty.py"

        ${installScripts}

        ${fixPrettyShSources}

        ${wrapPyYamlScripts}

        wrapProgram "$out/bin/cdn-proxy" \
          --prefix PATH : "${pkgs.curl}/bin"

        wrapProgram "$out/bin/enable-vpn-hybrid" \
          --prefix PYTHONPATH : "${pkgs.python3Packages.pyyaml}/${pkgs.python3.sitePackages}"

        wrapProgram "$out/bin/start-hybrid-vpn" \
          --prefix PATH : "${pkgs.iproute2}/bin:${pkgs.curl}/bin:${pkgs.procps}/bin"

        wrapProgram "$out/bin/manual-tun-routes" \
          --prefix PATH : "${pkgs.iproute2}/bin:${pkgs.curl}/bin:${pkgs.procps}/bin"

        wrapProgram "$out/bin/test-browser-vpn" \
          --prefix PATH : "${pkgs.iproute2}/bin:${pkgs.curl}/bin:${pkgs.iptables}/bin"

        wrapProgram "$out/bin/check-vpn-status" \
          --prefix PATH : "${pkgs.curl}/bin:${pkgs.procps}/bin"
      '';
  };
in

lib.mkIf cfg.enable {
  environment.systemPackages = [ vpnScriptsPkg ];
}
