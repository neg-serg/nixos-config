{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "chromium-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "duquesnay";
    repo = "mcp-chromium-cdp";
    rev = "1a4aca12df30bdb095f91d1f68680b06d3d3ec75";
    hash = "sha256-jFAjaYdknxUqi6E+l4JyfH03Kmq4dyamwXRGLFBzIwQ=";
  };

  npmDepsHash = "sha256-rBpLwO5TaOJ5TnC2OoezIdqRQvSIQ9x3MXY6Fc+zDsk=";

  meta = with lib; {
    description = "Chromium CDP MCP server";
    homepage = "https://github.com/duquesnay/mcp-chromium-cdp";
    license = licenses.mit;
    mainProgram = "mcp-chromium-cdp";
    platforms = platforms.unix;
  };
}
