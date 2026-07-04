{ lib, buildGoModule, webkitgtk_4_1, gtk3, libsoup_3
, glib-networking, gsettings-desktop-schemas, librsvg
, pkg-config, nodejs, fetchFromGitHub
}:

buildGoModule rec {
  pname = "gituserchrome";
  version = "1.2";

  src = fetchFromGitHub {
    owner = "soulhotel";
    repo = "git-userChrome";
    rev = "ef32800ae8ffd3f0e2a3e72bc7daf6677c96c038";
    hash = "sha256-W9Mqq7+hQFJKQkGWkUZzFuwFPIlZah8oJvs93eVcCpk=";
  };

  vendorHash = "sha256-SqC64ztN1TeGpoVZyeM9b+0FF+AOLSasZuancKDP7WA=";

  tags = [ "desktop" "production" ];

  ldflags = [ "-s" "-w" ];

  # Prevent frontend build from leaking into goModules
  overrideModAttrs = old: {
    preBuild = "";
  };

  nativeBuildInputs = [ pkg-config nodejs ];

  buildInputs = [
    webkitgtk_4_1
    gtk3
    libsoup_3
    glib-networking
    gsettings-desktop-schemas
    librsvg
  ];

  buildPhase = ''
    runHook preBuild

    # Build the Vite frontend so Go's //go:embed can find it
    export HOME="$TMPDIR"
    pushd frontend/src
    npm install
    npm run build
    popd

    # Build Go binary with Wails/webkit2gtk support
    CGO_ENABLED=1 go build \
      -tags "$(IFS=, ; echo "''${tags[*]}")" \
      -ldflags "''${ldflags[*]}" \
      -o gituserChrome \
      .

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp gituserChrome $out/bin/
    runHook postInstall
  '';

  meta = with lib; {
    description = "A cross-platform tool to git userChrome themes from anywhere";
    homepage = "https://github.com/soulhotel/git-userChrome";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "gituserChrome";
    platforms = [ "x86_64-linux" ];
  };
}
