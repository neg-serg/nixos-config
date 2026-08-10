{
  pkgs,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.librsvg # Small library to render SVG images to Cairo surfaces
    pkgs.libxml2 # XML parsing library for C
  ];
}
