{
  lib,
  python3Packages,
  fetchFromGitHub,
  makeWrapper,
}: let
  inherit (python3Packages) python;
  deps = with python3Packages; [
    fastmcp
    pydantic
  ];
in
  python3Packages.buildPythonApplication rec {
    pname = "meeting-notes-mcp";
    version = "0.1.0";
    format = "other";

    src = fetchFromGitHub {
      owner = "Claire-s-Monster";
      repo = "claudecode-session-notes";
      rev = "c11a48b1c060100e7f465b6f53a65a981a6ce1ba";
      hash = "sha256-niCJ0YO7bhERT1i047IqI+ZFN7WKEp6jiU5zxPD0fL0=";
    };

    propagatedBuildInputs = deps;
    nativeBuildInputs = [makeWrapper];

    dontBuild = true;

    installPhase = ''
      runHook preInstall
      site="$out/libexec/meeting-notes-mcp"
      mkdir -p "$site"
      cp -r src pyproject.toml README.md "$site/"
      runHook postInstall
    '';

    postInstall = ''
      site="$out/libexec/meeting-notes-mcp"
      makeWrapper ${python}/bin/python $out/bin/meeting-notes-mcp \
        --set PYTHONPATH "$site:${python3Packages.makePythonPath deps}" \
        --add-flags "$site/src/session_notes/server.py"
    '';

    meta = with lib; {
      description = "Meeting notes / session tracking MCP server";
      homepage = "https://github.com/Claire-s-Monster/claudecode-session-notes";
      license = licenses.mit;
      mainProgram = "meeting-notes-mcp";
      platforms = platforms.unix;
    };
  }
