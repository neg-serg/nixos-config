{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "agenda-mcp";
  version = "0.1.0";
  pyproject = true;
  src = ./src;

  nativeBuildInputs = [python3Packages.hatchling];
  propagatedBuildInputs = [
    python3Packages.mcp
    python3Packages.pydantic
    python3Packages.ics
    python3Packages.python-dateutil
    python3Packages.tzlocal
  ];

  pythonImportsCheck = ["agenda_mcp"];

  meta = with lib; {
    description = "Agenda/timeline MCP server for calendars and reminders";
    homepage = "https://github.com/neg-serg/dotfiles";
    license = licenses.mit;
    mainProgram = "agenda-mcp";
    platforms = platforms.unix;
  };
}
