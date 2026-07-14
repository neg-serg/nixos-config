final: prev: {

  ghgrab = final.stdenv.mkDerivation {
    pname = "ghgrab";
    version = "2.0.1";

    src = final.fetchurl {
      url = "https://github.com/abhixdd/ghgrab/releases/download/v2.0.1/ghgrab-linux";
      hash = "sha256-+pb0Z/VO+1wbZdaelQtciBXGoZqO7DXnSV40ln/fNPU=";
    };

    dontUnpack = true;

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/ghgrab"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Search and download files from GitHub without leaving your CLI";
      homepage = "https://github.com/abhixdd/ghgrab";
      license = licenses.mit;
      mainProgram = "ghgrab";
      platforms = [ "x86_64-linux" ];
    };
  };

  lazytail = final.stdenv.mkDerivation {
    pname = "lazytail";
    version = "0.10.0";

    src = final.fetchurl {
      url = "https://github.com/raaymax/lazytail/releases/download/v0.10.0/lazytail-linux-x86_64.tar.gz";
      hash = "sha256-Ks94hsUJ6eT3YRyvGj7nB27hFaLyvLNDN4xgJNcBjWQ=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 lazytail "$out/bin/lazytail"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "A fast, universal terminal-based log viewer with live filtering and follow mode";
      homepage = "https://github.com/raaymax/lazytail";
      license = licenses.mit;
      mainProgram = "lazytail";
      platforms = [ "x86_64-linux" ];
    };
  };

  reddix = final.stdenv.mkDerivation {
    pname = "reddix";
    version = "0.2.9";

    src = final.fetchurl {
      url = "https://github.com/ck-zhang/reddix/releases/download/v0.2.9/reddix-x86_64-unknown-linux-gnu.tar.xz";
      hash = "sha256-XRGV/mcpv+fUGwx8mq0S4eEcHrlTLWjZcEhh1BMXkgE=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 reddix-x86_64-unknown-linux-gnu/reddix "$out/bin/reddix"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Reddit, refined for the terminal";
      homepage = "https://github.com/ck-zhang/reddix";
      license = licenses.mit;
      mainProgram = "reddix";
      platforms = [ "x86_64-linux" ];
    };
  };

  repeater = final.stdenv.mkDerivation {
    pname = "repeater";
    version = "0.1.10";

    src = final.fetchurl {
      url = "https://github.com/shaankhosla/repeater/releases/download/v0.1.10/repeater-x86_64-unknown-linux-gnu.tar.xz";
      hash = "sha256-z54NDmhztJNJulheuYqaicxXYTsacMKU6tZx74B7sCY=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 repeater-x86_64-unknown-linux-gnu/repeater "$out/bin/repeater"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Spaced repetition, in your terminal";
      homepage = "https://github.com/shaankhosla/repeater";
      license = licenses.asl20;
      mainProgram = "repeater";
      platforms = [ "x86_64-linux" ];
    };
  };

  resterm = final.stdenv.mkDerivation {
    pname = "resterm";
    version = "0.41.1";

    src = final.fetchurl {
      url = "https://github.com/unkn0wn-root/resterm/releases/download/v0.41.1/resterm_Linux_x86_64";
      hash = "sha256-q0EnBwnDrrdrv+RHYKoxG805WFihL+Jr6YLLq6tu1kE=";
    };

    dontUnpack = true;

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/resterm"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Terminal REST client for .http/.rest files with HTTP, GraphQL and gRPC support";
      homepage = "https://github.com/unkn0wn-root/resterm";
      license = licenses.asl20;
      mainProgram = "resterm";
      platforms = [ "x86_64-linux" ];
    };
  };

  simutil = final.stdenv.mkDerivation {
    pname = "simutil";
    version = "0.5.0";

    src = final.fetchurl {
      url = "https://github.com/dungngminh/simutil/releases/download/v0.5.0/simutil-linux-x64.tar.gz";
      hash = "sha256-SyrDsZIdpXZ2WGfrPzdW+eBHXb2x4Pb7Elk+cvcQLZA=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 simutil-linux-x64 "$out/bin/simutil"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Cross platform utility TUI app for launching iOS simulators / Android emulators";
      homepage = "https://github.com/dungngminh/simutil";
      license = licenses.mit;
      mainProgram = "simutil";
      platforms = [ "x86_64-linux" ];
    };
  };

  strace-tui = final.stdenv.mkDerivation {
    pname = "strace-tui";
    version = "1.0.1";

    src = final.fetchurl {
      url = "https://github.com/Rodrigodd/strace-tui/releases/download/v1.0.1/strace-tui-x86_64-unknown-linux-gnu.tar.gz";
      hash = "sha256-t1eeN6DgHF6ndYQpL3ryhLHA4L8ZmYFmWCgjfw8npCw=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 strace-tui "$out/bin/strace-tui"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "TUI for visualizing and exploring strace output";
      homepage = "https://github.com/Rodrigodd/strace-tui";
      license = licenses.mit;
      mainProgram = "strace-tui";
      platforms = [ "x86_64-linux" ];
    };
  };

  v2raya = final.stdenv.mkDerivation {
    pname = "v2raya";
    version = "2.2.7.5";

    src = final.fetchurl {
      url = "https://github.com/v2rayA/v2rayA/releases/download/v2.2.7.5/v2raya_linux_x64_2.2.7.5";
      hash = "sha256-IuntzxicN1uqx21ZNTsqMp/QVS/gg8OTuntb+bkLIBE="; # FIXME: stone had file:// upstream; GitHub release URL needs verification
    };

    dontUnpack = true;

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/v2raya"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "A web GUI client of Project V";
      homepage = "https://github.com/v2rayA/v2rayA";
      license = licenses.agpl3Only;
      mainProgram = "v2raya";
      platforms = [ "x86_64-linux" ];
    };
  };

  watchtower = final.stdenv.mkDerivation {
    pname = "watchtower";
    version = "1.0.0";

    src = final.fetchurl {
      url = "https://github.com/lajosdeme/watchtower/releases/download/v1.0.0/watchtower_Linux_x86_64.tar.gz";
      hash = "sha256-8xVFQ4+IhxOT3QFVEoSEZiTVl3ejuxnw4ZxmUL4/ObE=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 watchtower "$out/bin/watchtower"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "A clean, minimal, terminal-based global intelligence dashboard";
      homepage = "https://github.com/lajosdeme/watchtower";
      license = licenses.mit;
      mainProgram = "watchtower";
      platforms = [ "x86_64-linux" ];
    };
  };

  witr = final.stdenv.mkDerivation {
    pname = "witr";
    version = "0.3.2";

    src = final.fetchurl {
      url = "https://github.com/pranshuparmar/witr/releases/download/v0.3.2/witr-linux-amd64";
      hash = "sha256-dGDP0Jn/QaJKCJ5vYESWwipB1GY3ScsRtAFAGYmOFtQ=";
    };

    dontUnpack = true;

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/witr"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "A Linux CLI tool that explains the causal chain behind running processes";
      homepage = "https://github.com/pranshuparmar/witr";
      license = licenses.asl20;
      mainProgram = "witr";
      platforms = [ "x86_64-linux" ];
    };
  };

}
