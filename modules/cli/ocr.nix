# OCR/docling tooling: Tesseract engine (eng/rus/osd), ocrmypdf for PDFs and
# docling for PDF/DOCX → Markdown (layout + table models).
{ pkgs, ... }:
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
  # ocrmypdf bundles its own tesseract from the python package — pass the
  # same language set through so Russian PDFs work out of the box.
  # unpaper: nixpkgs fetches it from flameeyes.eu, which stalls from this
  # region; the GitHub release asset is byte-identical (same sha256) and fast.
  unpaper = pkgs.unpaper.overrideAttrs {
    src = pkgs.fetchurl {
      url = "https://github.com/unpaper/unpaper/releases/download/unpaper-7.0.0/unpaper-7.0.0.tar.xz";
      hash = "sha256-JXX7vybCJxnRy4grWWAsmQDH90cRisEwiD9jQZvkaoA=";
    };
  };
  ocrmypdf = pkgs.python3.pkgs.toPythonApplication (
    pkgs.python3.pkgs.ocrmypdf.override { inherit tesseract unpaper; }
  );
  # Docling: PDF/DOCX → Markdown with layout/table models — the store-native
  # replacement for the marker-pdf pip venv that used to live in
  # ~/src/ai-tools (its interpreter went stale on a python bump and `marker`
  # has been dead since). Bound as a python env because the CLI ships with the
  # python package; Tesseract above stays the OCR engine for scanned pages.
  docling = pkgs.python3.withPackages (ps: [ ps.docling ]);
in
{
  environment.systemPackages = [
    tesseract # OCR engine (Tesseract) with eng/rus/osd language data
    ocrmypdf # add searchable text layer to PDFs via OCR (uses Tesseract)
    docling # PDF/DOCX → Markdown converter with layout and table detection
  ];
}
