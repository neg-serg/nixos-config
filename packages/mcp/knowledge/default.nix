{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "knowledge-mcp";
  version = "0.1.0";
  pyproject = true;
  src = ./src;

  nativeBuildInputs = [python3Packages.hatchling];
  propagatedBuildInputs = [
    python3Packages.mcp
    python3Packages.pydantic
    python3Packages.sentence-transformers
    python3Packages.numpy
    python3Packages."pdfminer-six"
  ];

  pythonImportsCheck = ["knowledge_mcp"];

  meta = with lib; {
    description = "Vector knowledge-base MCP server";
    homepage = "https://github.com/neg-serg/dotfiles";
    license = licenses.mit;
    mainProgram = "knowledge-mcp";
    platforms = platforms.unix;
  };
}
