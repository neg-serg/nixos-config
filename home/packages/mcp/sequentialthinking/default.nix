{
  lib,
  buildNpmPackage,
}:
buildNpmPackage rec {
  pname = "mcp-server-sequential-thinking";
  version = "0.6.2";

  src = ./src;

  npmDepsHash = "sha256-jMIZtWLUe8NEr9NkXeGLiRjm1X35liAYtsUFcjV8bFM=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
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
    description = "MCP server for sequential thinking and planning";
    homepage = "https://github.com/modelcontextprotocol/servers";
    license = licenses.mit;
    mainProgram = "mcp-server-sequential-thinking";
    platforms = platforms.unix;
  };
}
