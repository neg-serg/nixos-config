{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "two_percent";
  version = "0.12.18";

  src = fetchFromGitHub {
    owner = "kimono-koans";
    repo = "two_percent";
    rev = version;
    hash = "sha256-a4Z0p7AmUg/ComZXrzs6xSFBUXFsc1WplJnfxKfDJXs=";
  };

  cargoHash = "sha256-XkTjG3Q5DPrbqNhkC8atr1va9+pxTaP3ItnElv4V3DU=";

  meta = with lib; {
    description = "Skim fork tuned for low-latency fuzzy finding";
    homepage = "https://github.com/kimono-koans/two_percent";
    license = licenses.mit;
    mainProgram = "sk";
    platforms = platforms.unix;
    maintainers = with maintainers; [];
  };
}
