##
# Package: tewi
# Purpose: Text-based (TUI) interface for BitTorrent clients — manages
#   Transmission / qBittorrent / Deluge daemons (browse, add, control
#   torrents, edit labels, search providers). Talks to the local
#   transmission-daemon RPC (localhost:9091) out of the box.
# Notes:
#   - The PyPI project name is "tewi-torrent" but the sdist file is
#     tewi_torrent-2.5.0.tar.gz (underscore), so fetchPypi would construct a
#     404 URL — fetch the exact hash-layout URL instead (same pattern as
#     packages/tmd-top/default.nix).
#   - geoip2fast (peer-country lookup) is not in nixpkgs: packaged here as a
#     private pure-python derivation (bundles its own GeoIP database).
{
  lib,
  python3,
  fetchurl,
  fetchPypi,
  ...
}:
let
  pypi = python3.pkgs;

  # Peer-country lookup for the torrent list — not in nixpkgs, pure python.
  geoip2fast = pypi.buildPythonPackage {
    pname = "geoip2fast";
    version = "1.2.2";
    format = "setuptools";
    src = fetchPypi {
      pname = "geoip2fast";
      version = "1.2.2";
      hash = "sha256-OIFXAM7f6xl9UbS4czsNT3lls23hUUfBJVJxJPi0XWs=";
    };
    doCheck = false;
    pythonImportsCheck = [ "geoip2fast" ];
  };
in
pypi.buildPythonApplication rec {
  pname = "tewi";
  version = "2.5.0";
  format = "pyproject";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/16/17/4d4e2118b05f6d440aa3cedcd3416e8c00fd5b4a622a37f8fd454c843bbf/tewi_torrent-2.5.0.tar.gz";
    hash = "sha256-/lyyFKM5rb4ng7/EQag7xOhCLKW+JCsAFVEyl0ZVrfw=";
  };

  # neg.nvim-style pure-dark theme: register a custom Textual theme (pure black
  # background, blue accents, light blue-grey text) and make it the default;
  # the "d" key still toggles between it and the built-in light theme.
  patches = [ ./neg-theme.patch ];

  nativeBuildInputs = [
    pypi.setuptools
    pypi.wheel
  ];

  propagatedBuildInputs = [
    pypi.textual # TUI framework (>= 0.83.0)
    pypi.transmission-rpc # Transmission RPC client
    pypi.qbittorrent-api # qBittorrent API client
    pypi.platformdirs # config/profile dir resolution
    pypi.pyperclip # clipboard paste for adding torrent links
    geoip2fast # peer country lookup (GeoIP)
  ];

  doCheck = false;
  pythonImportsCheck = [
    "tewi"
    "tewi.app"
  ];

  meta = with lib; {
    description = "Text-based interface for BitTorrent clients (Transmission, qBittorrent, Deluge)";
    homepage = "https://github.com/anlar/tewi";
    license = licenses.gpl3Plus;
    platforms = platforms.all;
    mainProgram = "tewi";
    maintainers = [ ];
  };
}
