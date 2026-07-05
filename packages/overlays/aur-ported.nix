final: prev: {

  oports = final.stdenv.mkDerivation {
    pname = "oports";
    version = "0.1-git";

    src = final.fetchFromGitHub {
      owner = "sdushantha";
      repo = "oports";
      rev = "0000000000000000000000000000000000000000";
      hash = "sha256-0000000000000000000000000000000000000000000=";
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 oports "$out/bin/oports"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "A wrapper around ss -tunlp to display cleaner output";
      homepage = "https://github.com/sdushantha/oports";
      license = licenses.mit;
      mainProgram = "oports";
    };
  };

  paru = final.stdenv.mkDerivation {
    pname = "paru";
    version = "0.1-git";

    src = final.fetchFromGitHub {
      owner = "Morganamilo";
      repo = "paru";
      rev = "0000000000000000000000000000000000000000";
      hash = "sha256-0000000000000000000000000000000000000000000=";
    };

    nativeBuildInputs = with final; [
      cargo
      pkg-config
      rustc
    ];

    buildInputs = with final; [
      pacman
    ];

    buildPhase = ''
      runHook preBuild
      cargo build --release
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 target/release/paru "$out/bin/paru"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Feature packed AUR helper";
      homepage = "https://github.com/morganamilo/paru";
      license = licenses.gpl3Plus;
      mainProgram = "paru";
    };
  };

  pipemixer = final.stdenv.mkDerivation {
    pname = "pipemixer";
    version = "0.1-git";

    src = final.fetchFromGitHub {
      owner = "heather7283";
      repo = "pipemixer";
      rev = "0000000000000000000000000000000000000000";
      hash = "sha256-0000000000000000000000000000000000000000000=";
    };

    nativeBuildInputs = with final; [
      meson
      ninja
      pkg-config
    ];

    buildInputs = with final; [
      inih
      pipewire
      ncurses
    ];

    meta = with final.lib; {
      description = "TUI volume control app for pipewire";
      homepage = "https://github.com/heather7283/pipemixer";
      license = licenses.gpl3Plus;
      mainProgram = "pipemixer";
    };
  };

  rofi-file-browser-extended = final.stdenv.mkDerivation {
    pname = "rofi-file-browser-extended";
    version = "0.1-git";

    src = final.fetchFromGitHub {
      owner = "marvinkreis";
      repo = "rofi-file-browser-extended";
      rev = "0000000000000000000000000000000000000000";
      hash = "sha256-0000000000000000000000000000000000000000000=";
    };

    nativeBuildInputs = with final; [
      cmake
    ];

    buildInputs = with final; [
      rofi
    ];

    meta = with final.lib; {
      description = "Use rofi to quickly open files";
      homepage = "https://github.com/marvinkreis/rofi-file-browser-extended";
      license = licenses.mit;
      mainProgram = "rofi-file-browser-extended";
    };
  };

  snixembed = final.stdenv.mkDerivation {
    pname = "snixembed";
    version = "0.1-git";

    src = final.fetchgit {
      url = "https://git.sr.ht/~steef/snixembed";
      rev = "0000000000000000000000000000000000000000";
      hash = "sha256-0000000000000000000000000000000000000000000=";
    };

    nativeBuildInputs = with final; [
      pkg-config
      vala
    ];

    buildInputs = with final; [
      glib
      gtk3
      libdbusmenu-gtk3
    ];

    installPhase = ''
      runHook preInstall
      make install PREFIX="$out"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Proxy StatusNotifierItems as XEmbedded systemtray icons";
      homepage = "https://git.sr.ht/~steef/snixembed";
      license = licenses.isc;
      mainProgram = "snixembed";
    };
  };

  tanin = final.stdenv.mkDerivation {
    pname = "tanin";
    version = "0.1-git";

    src = final.fetchFromGitHub {
      owner = "AnonMiraj";
      repo = "Tanin";
      rev = "0000000000000000000000000000000000000000";
      hash = "sha256-0000000000000000000000000000000000000000000=";
    };

    nativeBuildInputs = with final; [
      cargo
      pkg-config
      rustc
    ];

    buildInputs = with final; [
      alsa-lib
      openssl
      opus
    ];

    buildPhase = ''
      runHook preBuild
      cargo build --release --no-default-features
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 target/release/tanin "$out/bin/tanin"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "A TUI ambient sound generator written in Rust";
      homepage = "https://github.com/AnonMiraj/Tanin";
      license = licenses.mit;
      mainProgram = "tanin";
    };
  };

  xdg-desktop-portal-termfilechooser-hunkyburrito = final.stdenv.mkDerivation {
    pname = "xdg-desktop-portal-termfilechooser-hunkyburrito";
    version = "0.1-git";

    src = final.fetchFromGitHub {
      owner = "hunkyburrito";
      repo = "xdg-desktop-portal-termfilechooser";
      rev = "0000000000000000000000000000000000000000";
      hash = "sha256-0000000000000000000000000000000000000000000=";
    };

    nativeBuildInputs = with final; [
      meson
      ninja
      pkg-config
      scdoc
    ];

    buildInputs = with final; [
      inih
      systemd
      xdg-desktop-portal
    ];

    mesonFlags = [
      "-Dsd-bus-provider=libsystemd"
    ];

    meta = with final.lib; {
      description = "xdg-desktop-portal backend for terminal file choosers (hunkyburrito fork)";
      homepage = "https://github.com/hunkyburrito/xdg-desktop-portal-termfilechooser";
      license = licenses.mit;
    };
  };

  # AUR-bin

  act = final.stdenv.mkDerivation {
    pname = "act";
    version = "0.2.89";

    src = final.fetchurl {
      url = "https://github.com/nektos/act/releases/download/v0.2.89/act_Linux_x86_64.tar.gz";
      hash = "sha256-AZHW8fO3FrXFWCADJgXQX8PBzb9YHr7/ZVAZ5d0VJMA=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 act "$out/bin/act"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Run your GitHub Actions locally";
      homepage = "https://github.com/nektos/act";
      license = licenses.mit;
      mainProgram = "act";
      platforms = [ "x86_64-linux" ];
    };
  };

  eilmeldung = final.stdenv.mkDerivation {
    pname = "eilmeldung";
    version = "1.5.3";

    src = final.fetchurl {
      url = "https://github.com/christo-auer/eilmeldung/releases/download/1.5.3/eilmeldung-x86_64-unknown-linux-musl-1.5.3.tar.gz";
      hash = "sha256-vvuFk07crYBRKq2I2mLcQBJxgTnVOoSeCt8lhsjJzTQ=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 eilmeldung/eilmeldung "$out/bin/eilmeldung"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "A TUI RSS reader based on the news-flash library";
      homepage = "https://github.com/christo-auer/eilmeldung";
      license = licenses.gpl3Plus;
      mainProgram = "eilmeldung";
      platforms = [ "x86_64-linux" ];
    };
  };

  fsel = final.stdenv.mkDerivation {
    pname = "fsel";
    version = "3.5.1";

    src = final.fetchurl {
      url = "https://github.com/Mjoyufull/fsel/releases/download/3.5.1/fsel-x86_64-unknown-linux-gnu.tar.xz";
      hash = "sha256-R2fVH4ESWwNRz7nIDCL8Bm1RC38Zo6txV3v0oaWccIk=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 fsel-x86_64-unknown-linux-gnu/fsel "$out/bin/fsel"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Fast TUI app launcher and fuzzy finder";
      homepage = "https://github.com/Mjoyufull/fsel";
      license = licenses.bsd2;
      mainProgram = "fsel";
      platforms = [ "x86_64-linux" ];
    };
  };

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

  gmap = final.stdenv.mkDerivation {
    pname = "gmap";
    version = "0.4.0";

    src = final.fetchurl {
      url = "https://github.com/marawny/gmap/releases/download/v0.4.0/gmap-linux-x86_64-0.4.0.zip";
      hash = "sha256-+/ZDZWvy0MN0rUtsFVUMbEiIvYhAPz3FwdZftQ5p3qI=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
      final.unzip
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 gmap "$out/bin/gmap"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Git repository analysis tool for churn and heatmap visualization";
      homepage = "https://github.com/marawny/gmap";
      license = licenses.mit;
      mainProgram = "gmap";
      platforms = [ "x86_64-linux" ];
    };
  };

  gowall = final.stdenv.mkDerivation {
    pname = "gowall";
    version = "0.2.4";

    src = final.fetchurl {
      url = "https://github.com/Achno/gowall/releases/download/v0.2.4/gowall-amd64-linux.tar.gz";
      hash = "sha256-2rSG1QKOX3kPvZLdJgIqxWcLDQGt70vWMrpxFcLTStM=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 gowall "$out/bin/gowall"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "A tool to convert a Wallpaper's color scheme - palette";
      homepage = "https://github.com/Achno/gowall";
      license = licenses.mit;
      mainProgram = "gowall";
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

  protonup-rs = final.stdenv.mkDerivation {
    pname = "protonup-rs";
    version = "0.12.1";

    src = final.fetchurl {
      url = "https://github.com/auyer/Protonup-rs/releases/download/v0.12.1/protonup-rs-linux-amd64.tar.gz";
      hash = "sha256-ExlF9U/hOsABF5ImVImoISQNT7HZwv57MNx3892VfiU=";
    };

    nativeBuildInputs = [
      final.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 protonup-rs "$out/bin/protonup-rs"
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "CLI program to automate the installation and update of Proton-GE";
      homepage = "https://github.com/auyer/Protonup-rs";
      license = licenses.asl20;
      mainProgram = "protonup-rs";
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
