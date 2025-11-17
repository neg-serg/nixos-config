{
  lib,
  python3Packages,
  makeWrapper,
}:
let
  inherit (python3Packages) python;
  deps = with python3Packages; [
    mcp
    redis
    python-dotenv
  ];
in
python3Packages.buildPythonApplication rec {
  pname = "mcp-server-redis";
  version = "0.1.0";
  format = "other";
  src = ./.;

  propagatedBuildInputs = deps;
  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    site="$out/libexec/mcp-server-redis"
    mkdir -p "$site"
    cp -r src/* "$site/"
    runHook postInstall
  '';

  postInstall = ''
    site="$out/libexec/mcp-server-redis"
    makeWrapper ${python}/bin/python $out/bin/mcp-server-redis \
      --set PYTHONPATH "$site:${python3Packages.makePythonPath deps}" \
      --add-flags "$site/main.py"
  '';

  meta = with lib; {
    description = "Simple Redis MCP server";
    homepage = "https://github.com/prajwalnayak7/mcp-server-redis";
    license = licenses.mit;
    mainProgram = "mcp-server-redis";
    platforms = platforms.unix;
  };
}
