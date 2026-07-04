{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation rec {
  pname = "andromeda-gtk-theme";
  version = "unstable-2026-05-19";

  src = fetchFromGitHub {
    owner = "EliverLara";
    repo = "Andromeda-gtk";
    rev = "ff0f40e1cfa95110199eda83b4b459bd0cedd44e";
    hash = "sha256-L6TgTBsOV46HsLSArYsG2CGM7WCsbtdq1nRkO4dsw9E=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    theme_root="$out/share/themes/Andromeda"
    mkdir -p "$theme_root"
    cp "$src/index.theme" "$theme_root/"
    for dir in assets gtk-2.0 gtk-3.0 gtk-4.0 gnome-shell cinnamon metacity-1 xfwm4; do
      if [ -d "$src/$dir" ]; then
        cp -r "$src/$dir" "$theme_root/$dir"
      fi
    done
    runHook postInstall
  '';

  meta = with lib; {
    description = "Andromeda — an elegant dark GTK theme for Gnome, MATE, Budgie, Cinnamon, XFCE";
    homepage = "https://github.com/EliverLara/Andromeda-gtk";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    maintainers = with maintainers; [ ];
  };
}
