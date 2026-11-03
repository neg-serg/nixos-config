# OCR tooling: Tesseract engine (eng/rus/osd) and ocrmypdf for PDFs.
#
# Docling (PDF/DOCX → Markdown, layout + table models) is no longer part of the
# system closure: its python env is ~3.9 GiB and only needed on demand. Run it
# as `nix run .#docling -- file.pdf` or from the `ai` devshell, where `docling`
# is on PATH; pdf2md (packages/local-bin-system) resolves it from PATH too.
{ pkgs, config, ... }:
let
  # Default tesseract ships eng only; rus needed for Russian text, osd for
  # orientation/script detection on scans.
  tesseract = pkgs.tesseract.override {
    enableLanguages = [
      "eng"
      "rus"
      "osd"
    ];
  };
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in
{
  environment.systemPackages = [
    tesseract # OCR engine (Tesseract) with eng/rus/osd language data
    (onDemand {
      name = "ocrmypdf";
      attr = "ocrmypdf";
    }) # add searchable text layer to PDFs via OCR, built on first use
  ];
}
