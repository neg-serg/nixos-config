{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "mcp-server-browserbase";
  version = "2.4.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@browserbasehq/mcp-server-browserbase/-/mcp-server-browserbase-${version}.tgz";
    hash = "sha256-IcY/XSROHdmE0rCJvsA8Xf+fglIBVrsTHXWcWJgFv5Y=";
  };

  npmDepsHash = "sha256-NjBidgBK1tlMb6+15wXHzBk9GEIymKmD7IMTFNPDnKI=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace '"prepare": "husky && pnpm build",' ""
  '';

  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  npmInstallFlags = npmFlags;
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    runHook postBuild
  '';

  meta = with lib; {
    description = "Browser automation MCP server using Browserbase";
    homepage = "https://github.com/browserbase/mcp-server-browserbase";
    license = licenses.asl20;
    mainProgram = "mcp-server-browserbase";
    platforms = platforms.unix;
  };
}
