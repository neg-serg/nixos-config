{
  lib,
  python3Packages,
  fetchFromGitHub,
  makeWrapper,
}: let
  inherit (python3Packages) python;
  deps = with python3Packages; [
    fastmcp
    python-dotenv
    requests
  ];
in
  python3Packages.buildPythonApplication rec {
    pname = "smtp-mcp";
    version = "0.1.0";
    format = "other";

    src = fetchFromGitHub {
      owner = "Nels2";
      repo = "smtp-mcp-server";
      rev = "68d0015953e2b31ba1e3859d2567c164958b80c7";
      hash = "sha256-wRJBxxeWk3Yof1KRI5JVywZGnFKsJJhm0aZE0UtLQgU=";
    };

    patches = [./env-config.patch];

    propagatedBuildInputs = deps;
    nativeBuildInputs = [makeWrapper];

    dontBuild = true;

    installPhase = ''
      runHook preInstall
      site="$out/libexec/smtp-mcp"
      mkdir -p "$site"
      cp -r . "$site/"
      runHook postInstall
    '';

    postInstall = ''
      site="$out/libexec/smtp-mcp"
      makeWrapper ${python}/bin/python $out/bin/smtp-mcp \
        --set PYTHONPATH "$site:${python3Packages.makePythonPath deps}" \
        --add-flags "$site/mcp_email.py"
    '';

    meta = with lib; {
      description = "Simple SMTP MCP server";
      homepage = "https://github.com/Nels2/smtp-mcp-server";
      license = licenses.mit;
      mainProgram = "smtp-mcp";
      platforms = platforms.unix;
    };
  }
