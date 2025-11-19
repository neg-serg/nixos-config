{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "discord-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "v-3";
    repo = "discordmcp";
    rev = "39622af0333bcd324e811a2390146927517fb03d";
    hash = "sha256-zmWU9zDEJDvH0ywW990DgbDTdlxyQ8OIQ1okEUQNIuY=";
  };

  npmDepsHash = "sha256-ONRO9smF8JSD1C5Xr4q3sET+83OaRqTbGxRbiryYg9A=";

  meta = with lib; {
    description = "Discord MCP server";
    homepage = "https://github.com/v-3/discordmcp";
    license = licenses.mit;
    mainProgram = "discordmcp";
    platforms = platforms.unix;
  };
}
