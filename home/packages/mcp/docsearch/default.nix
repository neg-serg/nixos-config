{
  lib,
  buildNpmPackage,
}:
buildNpmPackage rec {
  pname = "docsearch-mcp";
  version = "0.0.6";

  src = ./src;

  npmDepsHash = "sha256-6FZSPJn1Poo4GOdobMMxRVqHkiuGLNWPUyh1JUqfTG0=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace '"prepare": "tsc",' ""
  '';

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = ["--ignore-scripts"];

  meta = with lib; {
    description = "Document search MCP server";
    homepage = "https://github.com/patrickkoss/docsearch-mcp";
    license = licenses.asl20;
    mainProgram = "docsearch-mcp";
    platforms = platforms.unix;
  };
}
