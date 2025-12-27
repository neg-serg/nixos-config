{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  cairo,
  glib,
  pango,
}:
rustPlatform.buildRustPackage rec {
  pname = "rofi-games";
  version = "1.16.0";

  src = fetchFromGitHub {
    owner = "Rolv-Apneseth";
    repo = "rofi-games";
    rev = "v${version}";
    hash = "sha256-sPUqWuE8yte8SouxJZlCTfxvJYXBozRtzPEPLovfIF4=";
  };

  cargoHash = "sha256-jfZgb8aTvP81mhvieKf9Dfme3ilU469LCxco0pL3EMw=";

  nativeBuildInputs = [
    pkg-config # discover C libs for build
  ];

  buildInputs = [
    cairo # 2D graphics
    glib # core GNOME/GLib utils
    pango # text layout
  ];

  meta = with lib; {
    description = "A rofi plugin which adds a mode that will list available games for launch along with their box art. Requires a good theme for the best results";
    homepage = "https://github.com/Rolv-Apneseth/rofi-games";
    license = licenses.gpl2Only;
    maintainers = with maintainers; [];
    mainProgram = "rofi-games";
  };
}
