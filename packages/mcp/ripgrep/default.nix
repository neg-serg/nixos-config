{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "mcp-ripgrep";
  version = "0.4.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/mcp-ripgrep/-/mcp-ripgrep-${version}.tgz";
    hash = "sha256-HaXPiZTf56ffyX8QpC5XJcfKp1s+D9A6kG/mihyHeH0=";
  };

  npmDepsHash = "sha256-9ZJ2uXVch2hPGvj5tTh1aPiD1rWaG26twB54opcMlZE=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace dist/index.js \
      --replace 'const path = String(args.path);' \
                'const path = String(args.path ?? process.env.MCP_RIPGREP_ROOT ?? ".");'
  '';

  npmInstallFlags = ["--ignore-scripts"];
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    runHook postBuild
  '';

  meta = with lib; {
    description = "Ripgrep-backed search MCP server";
    homepage = "https://github.com/mcollina/mcp-ripgrep";
    license = licenses.mit;
    mainProgram = "mcp-ripgrep";
    platforms = platforms.unix;
    maintainers = [];
  };
}
