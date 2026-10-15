{
  stdenvNoCC,
  fetchFromGitHub,
  lib,
  hyprcursor,
  xcur2png,
}:
stdenvNoCC.mkDerivation rec {
  pname = "Alkano-aio";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "Alkano-aio";
    rev = "v${version}";
    sha256 = "sha256-N+pM7TBtpQxk4Y/2TG2q7U8L3w44UkaAn1d9/kDeN8g=";
  };

  nativeBuildInputs = [
    hyprcursor # hyprcursor-util (extract/create)
    xcur2png # runtime dep of `hyprcursor-util --extract`
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/icons
    cp -r Alkano-aio/ $out/share/icons

    # Upstream is an XCursor-only theme. hyprcursor (Hyprland's native cursor
    # loader) refuses a theme without manifest.hl — libhyprcursor's
    # themeAccessible() checks exactly that — so Hyprland silently fell back to
    # XCursor and HYPRCURSOR_THEME pointed at nothing. Compile the hyprcursor
    # assets from the xcursor theme and ship them in the same theme directory,
    # which is where both loaders look for `Alkano-aio`.
    work="$(mktemp -d)"
    hyprcursor-util --extract "$out/share/icons/Alkano-aio" -o "$work"
    hyprcursor-util --create "$work/extracted_Alkano-aio" -o "$work"
    # hyprcursor-util names the output `theme_$NAME`, and the extracted name
    # comes from index.theme ("Extracted Theme"), hence the glob.
    cp -r "$work"/theme_*/. "$out/share/icons/Alkano-aio/"

    runHook postInstall
  '';

  meta = {
    description = "Mirror of Alkano-aio";
    homepage = "https://github.com/neg-serg/Alkano-aio";
    license = lib.licenses.gpl3;
    platforms = lib.platforms.all;
    maintainers = [ lib.maintainers.neg-serg ];
  };
}
