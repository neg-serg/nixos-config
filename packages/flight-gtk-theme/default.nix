{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation rec {
  pname = "flight-gtk-theme";
  version = "unstable-2025-06-13";

  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "Flight-Plasma-Themes";
    rev = "fdb26086f261ce0145c5f7b296f6bb34b188b9f1";
    hash = "sha256-te8wGbgcz/tXFFPnXouTw6JWIxYz61YmI8JXg6jNZdo=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    theme_root="$out/share/themes"
    mkdir -p "$theme_root"
    for variant in Flight-Dark-GTK Flight-light-GTK; do
      if [ -d "$src/$variant" ]; then
        cp -r "$src/$variant" "$theme_root/$variant"
      fi
    done
    runHook postInstall
  '';

  meta = with lib; {
    description = "Flight GTK theme (dark and light variants)";
    homepage = "https://github.com/neg-serg/Flight-Plasma-Themes";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
