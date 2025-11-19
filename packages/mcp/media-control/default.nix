{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "media-mcp";
  version = "0.1.0";
  pyproject = true;
  src = ./src;

  nativeBuildInputs = [python3Packages.hatchling];
  propagatedBuildInputs = with python3Packages; [
    mcp
    pydantic
    mpd2
  ];

  pythonImportsCheck = ["media_mcp"];

  meta = with lib; {
    description = "Media assistant MCP server for MPD and PipeWire";
    homepage = "https://github.com/neg-serg/dotfiles";
    license = licenses.mit;
    mainProgram = "media-mcp";
    platforms = platforms.unix;
  };
}
