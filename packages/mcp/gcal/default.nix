{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "gcal-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "teren-papercutlabs";
    repo = "gcal-mcp";
    rev = "b3a5e4cac1e8516575dd7aebfbbd8151cfc0530f";
    hash = "sha256-UFIHsNjajV9pV+o6gT5zocndajYN8JbLg3FqCpsRx8c=";
  };

  patches = [./env-refresh.patch];

  npmDepsHash = "sha256-vER8pds/OcOASkgHDQrCFzZtuuDp1g08Ejbl+vbPEPQ=";

  meta = with lib; {
    description = "Google Calendar MCP server";
    homepage = "https://github.com/teren-papercutlabs/gcal-mcp";
    license = licenses.mit;
    mainProgram = "gcal-mcp";
    platforms = platforms.unix;
  };
}
