{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "gitlab-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "zereight";
    repo = "gitlab-mcp";
    rev = "9202826b2431e42d5272e2e2a63d62dbf6e1fa8d";
    hash = "sha256-2nT+TkBGtFK3GHoK+pStA5R8sNhCJY8Fz6JlZ/tKxjs=";
  };

  npmDepsHash = "sha256-N/N87/DCrv4E0MZk3641cNxkFv2skDimNpaUYKRDidY=";

  meta = with lib; {
    description = "GitLab MCP server";
    homepage = "https://github.com/zereight/gitlab-mcp";
    license = licenses.mit;
    mainProgram = "gitlab-mcp";
    platforms = platforms.unix;
  };
}
