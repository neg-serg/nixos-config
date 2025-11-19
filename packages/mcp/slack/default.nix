{
  lib,
  buildNpmPackage,
}:
buildNpmPackage rec {
  pname = "mcp-server-slack";
  version = "0.6.2";

  src = ./src;

  npmDepsHash = "sha256-4h2DAplkh2HwT2MqiTtg2QLfQS357EN8C4ZSUT+/iR4=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace '"prepare": "npm run build",' ""
  '';

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = npmFlags;

  meta = with lib; {
    description = "Slack MCP server";
    homepage = "https://github.com/modelcontextprotocol/servers-archived";
    license = licenses.mit;
    mainProgram = "mcp-server-slack";
    platforms = platforms.unix;
  };
}
