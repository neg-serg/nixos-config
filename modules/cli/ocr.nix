# OCR tooling: Tesseract engine (eng/rus/osd) and ocrmypdf for PDFs.
#
# Docling (PDF/DOCX → Markdown, layout + table models) stays out of the system
# closure: its python env is ~3.9 GiB. The `docling` launcher below builds the
# flake attr `docling-env` on first use and GC-roots it under $HOME; `nix run
# .#docling -- file.pdf` and the `ai` devshell reach the same env; pdf2md
# (packages/local-bin-system) resolves `docling` from PATH.
#
# The first conversion downloads ~500 MiB of layout/table models into
# ~/.cache/huggingface; later runs are offline.
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
    (onDemand {
      name = "docling";
      attr = "docling-env";
    }) # PDF/DOCX → Markdown with layout/table models, built on first use
  ];
}
