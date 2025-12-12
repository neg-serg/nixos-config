{
  lib,
  python3,
  fetchFromGitHub,
  fetchurl,
}: let
  geoip2fast = python3.pkgs.buildPythonPackage rec {
    pname = "geoip2fast";
    version = "1.2.2";
    pyproject = true;

    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/source/g/geoip2fast/geoip2fast-${version}.tar.gz";
      hash = "sha256-OIFXAM7f6xl9UbS4czsNT3lls23hUUfBJVJxJPi0XWs=";
    };

    build-system = [python3.pkgs.setuptools];

    pythonImportsCheck = ["geoip2fast"];

    meta = with lib; {
      description = "Fast GeoIP2 lookup library with bundled data";
      homepage = "https://github.com/rabuchaim/geoip2fast";
      license = licenses.mit;
      maintainers = with maintainers; [];
      platforms = platforms.unix;
    };
  };
in
  python3.pkgs.buildPythonApplication rec {
    pname = "tewi";
    version = "2.0.0";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "anlar";
      repo = "tewi";
      rev = "3541f3d546c377ff53f9ef205f7251e1480a31ba";
      hash = "sha256-5QVF/4tdZmCVEw9X9A3hokfjBED1iJ8Pj0w68f+Lu4k=";
    };

    postPatch = ''
      cat >> src/tewi/app.tcss <<'EOF'
      $primary: #000000;
      $secondary: #010101;
      $background: #010101;
      $surface: #010101;
      $success: #1a3a2a;
      $warning: #FFAA01;
      $error: #CF4F88;
      $accent: #010101;
      $text: #6C7E96;
      $text-muted: #3D3D3D;

      * {
          background: #010101 !important;
          text-opacity: 100% !important;
          scrollbar-background: #010101;
          scrollbar-color: #6C7E96;
      }

      TorrentItemOneline > #speed > #stats {
          text-opacity: 100%;
          color: #6C7E96;
      }

      TorrentItemCompact > #speed > #stats {
          text-opacity: 100%;
          color: #6C7E96;
      }

      TorrentItemCard > #stats > .column {
          text-opacity: 100%;
          color: #6C7E96;
      }

      Screen {
          background: #010101;
      }

      Header {
          background: #010101;
          color: #6C7E96;
      }

      Footer {
          background: #010101;
          color: #6C7E96;
      }

      ListItem.-highlight > TorrentItemOneline,
      ListItem.-highlight > TorrentItemCompact,
      ListItem.-highlight > TorrentItemCard {
          background: #0d1824 !important;
          color: #6C7E96;
      }

      ProgressBar > .bar--complete {
          color: #1a3a2a;
      }

      ProgressBar > .bar--indeterminate {
          color: #6C7E96;
      }

      DataTable > .datatable--cursor {
          background: #0d1824;
          color: #6C7E96;
      }

      Button {
          background: #010101;
          color: #6C7E96;
      }

      Button:hover {
          background: #16191e;
          color: #6C7E96;
      }

      Input {
          background: #010101;
          color: #6C7E96;
          border: tall #16191e;
      }

      Input:focus {
          border: tall #3D3D3D;
      }

      .torrent-complete {
          background: #1a3a2a;
      }

      .torrent-incomplete {
          background: #3a2a1a;
      }

      .torrent-stop {
          background: #16191e;
      }

      #info-panel {
          background: #010101;
      }

      #state-panel {
          background: #010101;
      }

      StatePanel > .search {
          background: #010101;
      }

      #state-panel > .sort {
          background: #010101;
      }

      #state-panel > .filter {
          background: #010101;
      }

      #state-panel > .alt-speed {
          background: #010101;
      }

      .alt-speed-none > #state-panel > #alt-speed {
          background: #010101;
      }

      .filter-none > #state-panel > #filter {
          background: #010101;
      }

      #state-panel > .page {
          background: #010101;
      }

      #state-panel > .column {
          background: #010101;
      }

      #info-panel > .column {
          background: #010101;
      }

      ListView {
          background: #010101;
      }

      ListItem {
          background: #010101;
      }

      TorrentListPanel {
          background: #010101;
      }

      TorrentItemOneline {
          background: #010101;
      }

      TorrentItemCompact {
          background: #010101;
          border: none;
      }

      TorrentItemCard {
          background: #010101;
          border: none;
      }

      TorrentInfoPanel {
          background: #010101;
          border: none;
      }

      VerticalScroll {
          background: #010101;
      }

      Container {
          background: #010101;
      }

      Widget {
          background: #010101;
      }

      Static {
          background: #010101;
      }

      Label {
          background: #010101;
      }

      Horizontal {
          background: #010101;
      }

      Vertical {
          background: #010101;
      }

      #websearch-results {
          background: #010101;
      }

      TorrentWebSearch {
          background: #010101;
          border: none;
      }

      DataTable > .datatable--header {
          background: #010101;
          color: #6C7E96;
      }

      DataTable > .datatable--header-hover {
          background: #16191e;
          color: #6C7E96;
      }
      EOF
    '';

    build-system = [python3.pkgs.setuptools];

    nativeBuildInputs = [python3.pkgs.pythonRelaxDepsHook];

    dependencies = with python3.pkgs; [
      textual
      transmission-rpc
      geoip2fast
      pyperclip
      qbittorrent-api
    ];

    pythonImportsCheck = ["tewi"];

    doCheck = false;

    meta = with lib; {
      description = "Text-based interface for Transmission, qBittorrent and Deluge";
      homepage = "https://github.com/anlar/tewi";
      license = licenses.gpl3Plus;
      maintainers = with maintainers; [];
      platforms = platforms.unix;
      mainProgram = "tewi";
    };
  }
