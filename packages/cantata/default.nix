{
  stdenv,
  lib,
  fetchFromGitHub,
  cmake,
  pkg-config,
  qt6Packages,
  qtbase ? qt6Packages.qtbase,
  qtsvg ? qt6Packages.qtsvg,
  qttools ? qt6Packages.qttools,
  qtwayland ? qt6Packages.qtwayland,
  wrapQtAppsHook ? qt6Packages.wrapQtAppsHook,
  perl,
  python3,
  # Cantata doesn't build with cdparanoia enabled right now.
  withCdda ? false,
  cdparanoia,
  withCddb ? false,
  libcddb,
  withLame ? false,
  lame,
  withMusicbrainz ? false,
  libmusicbrainz5,
  withTaglib ? true,
  taglib,
  taglib_extras,
  withHttpStream ? true,
  qtmultimedia ? qt6Packages.qtmultimedia,
  gst_all_1,
  withReplaygain ? true,
  ffmpeg,
  speex,
  mpg123,
  withMtp ? true,
  libmtp,
  withOnlineServices ? true,
  withDevices ? true,
  udisks2,
  withDynamic ? true,
  withHttpServer ? true,
  withLibVlc ? false,
  libvlc,
  withStreams ? true,
}: let
  # Inter-dependencies.
  assertDep = cond: msg: lib.asserts.assertMsg cond msg;
  _assertCddb = assertDep (withCddb -> withCdda && withTaglib) "Cantata: CDDB requires CDDA + Taglib";
  _assertCdda = assertDep (withCdda -> withCddb && withMusicbrainz) "Cantata: CDDA requires CDDB + MusicBrainz";
  _assertLame = assertDep (withLame -> withCdda && withTaglib) "Cantata: LAME requires CDDA + Taglib";
  _assertMtp = assertDep (withMtp -> withTaglib) "Cantata: MTP requires Taglib";
  _assertMusicbrainz = assertDep (withMusicbrainz -> withCdda && withTaglib) "Cantata: MusicBrainz requires CDDA + Taglib";
  _assertOnline = assertDep (withOnlineServices -> withTaglib) "Cantata: Online services require Taglib";
  _assertReplaygain = assertDep (withReplaygain -> withTaglib) "Cantata: Replaygain requires Taglib";
  _assertLibVlc = assertDep (withLibVlc -> withHttpStream) "Cantata: LibVLC requires HTTP stream playback";

  fstat = enabled: flag: "-DENABLE_${flag}=${
    if enabled
    then "ON"
    else "OFF"
  }";
  withUdisks = withTaglib && withDevices;

  gst = with gst_all_1; [
    gstreamer
    gst-libav
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
  ];

  options = [
    {
      names = ["CDDB"];
      enable = withCddb;
      pkgs = [libcddb];
    }
    {
      names = ["CDPARANOIA"];
      enable = withCdda;
      pkgs = [cdparanoia];
    }
    {
      names = ["DEVICES_SUPPORT"];
      enable = withDevices;
      pkgs = [];
    }
    {
      names = ["DYNAMIC"];
      enable = withDynamic;
      pkgs = [];
    }
    {
      names = ["FFMPEG" "MPG123" "SPEEXDSP"];
      enable = withReplaygain;
      pkgs = [ffmpeg speex mpg123];
    }
    {
      names = ["HTTPS_SUPPORT"];
      enable = true;
      pkgs = [];
    }
    {
      names = ["HTTP_SERVER"];
      enable = withHttpServer;
      pkgs = [];
    }
    {
      names = ["HTTP_STREAM_PLAYBACK"];
      enable = withHttpStream;
      pkgs = [qtmultimedia];
    }
    {
      names = ["LAME"];
      enable = withLame;
      pkgs = [lame];
    }
    {
      names = ["LIBVLC"];
      enable = withLibVlc;
      pkgs = [libvlc];
    }
    {
      names = ["MTP"];
      enable = withMtp;
      pkgs = [libmtp];
    }
    {
      names = ["MUSICBRAINZ"];
      enable = withMusicbrainz;
      pkgs = [libmusicbrainz5];
    }
    {
      names = ["ONLINE_SERVICES"];
      enable = withOnlineServices;
      pkgs = [];
    }
    {
      names = ["STREAMS"];
      enable = withStreams;
      pkgs = [];
    }
    {
      names = ["TAGLIB" "TAGLIB_EXTRAS"];
      enable = withTaglib;
      pkgs = [taglib taglib_extras];
    }
    {
      names = ["UDISKS2"];
      enable = withUdisks;
      pkgs = [udisks2];
    }
  ];
in
  stdenv.mkDerivation rec {
    pname = "cantata";
    version = "3.3.1";

    src = fetchFromGitHub {
      owner = "nullobsi";
      repo = "cantata";
      rev = "a19efdf9649c50320f8592f07d82734c352ace9c";
      sha256 = "TVqgTYpHyU1OM9XddJ915GM1XQQrhH9V7yhSxQOaXRs=";
    };

    patches = [
      ./dont-check-for-perl-in-PATH.diff
      ./cantata-projectid.diff
    ];

    postPatch = ''
            patchShebangs playlists
            substituteInPlace gui/main.cpp \
              --replace "file.open(QIODevice::WriteOnly);" "(void)file.open(QIODevice::WriteOnly);"
            substituteInPlace mpd-interface/cuefile.cpp \
              --replace "f.open(QIODevice::ReadOnly | QIODevice::Text);" \
                        "if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) { return false; }"
            python3 - <<'PY'
      import re
      from pathlib import Path
      pat = re.compile(r'^(\s*)invalidateFilter\(\);\s*$', re.MULTILINE)
      for path in Path(".").rglob("*.cpp"):
          text = path.read_text()
          if "invalidateFilter();" not in text:
              continue
          new_text = pat.sub(lambda m: f"{m.group(1)}beginFilterChange();\n{m.group(1)}endFilterChange();", text)
          if new_text != text:
              path.write_text(new_text)
      PY
    '';

    buildInputs =
      [
        qtbase
        qtsvg
        qtwayland
        (perl.withPackages (ppkgs: with ppkgs; [URI]))
      ]
      ++ lib.flatten (builtins.catAttrs "pkgs" (builtins.filter (opt: opt.enable) options));

    nativeBuildInputs = [
      cmake
      pkg-config
      qttools
      wrapQtAppsHook
      python3
    ];

    cmakeFlags = lib.flatten (map (opt: map (name: fstat opt.enable name) opt.names) options);

    qtWrapperArgs = lib.optionals (withHttpStream && !withLibVlc) [
      "--prefix"
      "GST_PLUGIN_PATH"
      ":"
      "${lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gst}"
    ];

    meta = with lib; {
      description = "Graphical client for MPD";
      mainProgram = "cantata";
      homepage = "https://github.com/cdrummond/cantata";
      license = licenses.gpl3Only;
      maintainers = with maintainers; [peterhoeg];
      platforms = platforms.linux;
    };
  }
