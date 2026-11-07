# GridCraft — spreadsheet workbook editor (formulas, charts, pivot tables;
# XLSX/XLSB, ODS, CSV/TSV) plus its `gridcraft-cli` companion.
#
# Upstream: https://github.com/storytold/gridcraft (MIT OR Apache-2.0). Built
# from the release tag through lib/mkCraftApp.nix.
{
  neg,
  ...
}:
neg.functions.mkCraftApp {
  name = "gridcraft";
  version = "0.17.0";
  hash = "sha256-95YijEgD9A5DJpBTuPWpM8q3PasnLFChJOSICmtpRC4=";
  cargoHash = "sha256-Mb3HBd3fquTqMYkJ6m+j/+V7Yx5zg2a2LU3b98QEab4=";
  description = "Spreadsheet editor (XLSX/XLSB, ODS, CSV/TSV; formulas, charts, pivots)";
  homepage = "https://getartcraft.com/apps/gridcraft";
}
