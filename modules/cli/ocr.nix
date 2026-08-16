# OCR tooling: Tesseract engine (eng/rus/osd) + ocrmypdf for PDFs.
{ pkgs, ... }:
let
  # Default tesseract ships eng only; rus needed for Russian text, osd for
  # orientation/script detection on scans.
  tesseract = pkgs.tesseract.override {
    enableLanguages = [ "eng" "rus" "osd" ];
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
in
{
  environment.systemPackages = [
    tesseract # OCR engine (Tesseract) with eng/rus/osd language data
    ocrmypdf # add searchable text layer to PDFs via OCR (uses Tesseract)
  ];
}
