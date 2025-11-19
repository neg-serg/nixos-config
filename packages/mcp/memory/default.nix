{
  lib,
  buildNpmPackage,
}:
buildNpmPackage rec {
  pname = "mcp-server-memory";
  version = "2025.9.25";

  src = ./src;

  npmDepsHash = "sha256-tRIisJ5VgQ0BU/5cNPgo1wj3Pnw7GXI5R+p8EkkGm3A=";

  postPatch = ''
    cp ${../memory/package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace '"prepare": "npm run build",' ""
  '';

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = ["--ignore-scripts"];
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  meta = with lib; {
    description = "MCP server providing memory/knowledge graph tools";
    homepage = "https://github.com/modelcontextprotocol/servers";
    license = licenses.mit;
    mainProgram = "mcp-server-memory";
    platforms = platforms.unix;
  };
}
