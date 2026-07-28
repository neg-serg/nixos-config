{
  pkgs,
  lib,
  ...
}:
pkgs.mkShell {
  # light text processing and previewing tools
  nativeBuildInputs = [
    pkgs.recoll # metadata-based full-text desktop search tool
    pkgs.tesseract # OCR engine with multi-language support
  ];
}
