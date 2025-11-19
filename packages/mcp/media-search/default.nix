{
  lib,
  python3Packages,
  tesseract,
}:
python3Packages.buildPythonApplication rec {
  pname = "media-search-mcp";
  version = "0.1.0";
  pyproject = true;
  src = ./src;

  nativeBuildInputs = [python3Packages.hatchling];
  propagatedBuildInputs = [
    python3Packages.mcp
    python3Packages.pydantic
    python3Packages.pytesseract
    python3Packages.pillow
    python3Packages.rapidfuzz
    python3Packages."pdfminer-six"
    tesseract
  ];

  pythonImportsCheck = ["media_search"];

  meta = with lib; {
    description = "Local media/notes OCR search MCP server";
    homepage = "https://github.com/neg-serg/dotfiles";
    license = licenses.mit;
    mainProgram = "media-search-mcp";
    platforms = platforms.unix;
  };
}
