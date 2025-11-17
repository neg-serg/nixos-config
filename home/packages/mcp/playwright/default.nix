{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "playwright-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "playwright-mcp";
    rev = "c016643bf94c1e5bb8ab9efc270b8f269ff4c38c";
    hash = "sha256-Ksc/lnhMuvu4ykJvgKQSCpWvtLvolwauxXYsLNcQV4g=";
  };

  npmDepsHash = "sha256-r+fbb1WQH6ovHSmzxbgEouCJux4ipqRedtblLEC3Agg=";
  dontNpmBuild = true;

  postInstall = ''
    if [ -e "$out/bin/@playwright/mcp" ]; then
      mkdir -p "$out/bin"
      ln -s "@playwright/mcp" "$out/bin/playwright-mcp"
    fi
  '';

  meta = with lib; {
    description = "Playwright MCP server";
    homepage = "https://github.com/microsoft/playwright-mcp";
    license = licenses.mit;
    mainProgram = "playwright-mcp";
    platforms = platforms.unix;
  };
}
