{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  dbus,
  libx11,
  libxcursor,
  libxi,
  libglvnd,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
}:

# Upstream ships prebuilt binaries only (AppImage / deb / rpm / tar.gz); this
# packages the tar.gz. Both ELFs need nothing beyond glibc and libgcc_s, which
# autoPatchelfHook patches in. Everything else is loaded at runtime through
# dlopen by winit, wgpu and the X11/Wayland backends (sonames grepped out of the
# binary: libwayland-client/egl, libxkbcommon(-x11), libX11(-xcb), libXcursor,
# libXi, libxcb, libEGL, libvulkan, libdbus-1), so the dlopen path — the only
# one an ELF patcher cannot rewrite — is covered by an LD_LIBRARY_PATH wrapper.
stdenv.mkDerivation (finalAttrs: {
  pname = "rustgis";
  version = "0.6.0";

  src = fetchurl {
    name = "RustGIS-${finalAttrs.version}-linux-x86_64.tar.gz";
    url = "https://github.com/opengeos/RustGIS/releases/download/v${finalAttrs.version}/RustGIS-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-YzvqFxLDNpzkOqDV/86+mSj/LdEGgoDppqjDGiyUqXI=";
  };

  sourceRoot = "RustGIS-${finalAttrs.version}-linux-x86_64";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  # libgcc_s is the one shared object the ELFs actually NEED (besides libc).
  buildInputs = [ (lib.getLib stdenv.cc.cc) ];

  runtimeLibs = [
    dbus # libdbus-1: session bus for the keychain/portal integration
    libglvnd # libEGL/libGL: wgpu's GL fallback
    libxkbcommon # libxkbcommon and libxkbcommon-x11: key mapping
    vulkan-loader # libvulkan: wgpu's primary backend
    wayland # libwayland-client/libwayland-egl: native Wayland surface
    libx11 # libX11 and libX11-xcb
    libxcursor # cursor themes on X11
    libxi # XInput2 devices on X11
    libxcb # libxcb: the X11 connection transport
  ];

  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/applications $out/share/mime/packages \
      $out/share/icons/hicolor/512x512/apps $out/share/doc/rustgis

    for bin in rustgis rustgis-cli; do
      install -Dm755 "$bin" "$out/bin/$bin"
      wrapProgram "$out/bin/$bin" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath finalAttrs.runtimeLibs}"
    done

    # Upstream desktop entry and MIME definition (`.rgis`/`.rgisx` project
    # files, GeoJSON); the icon is the 512x512 PNG shipped next to the binary.
    install -Dm644 rustgis.desktop $out/share/applications/rustgis.desktop
    install -Dm644 rustgis-mime.xml $out/share/mime/packages/rustgis-mime.xml
    install -Dm644 rustgis.png $out/share/icons/hicolor/512x512/apps/rustgis.png

    install -Dm644 LICENSE README.md THIRD-PARTY-LICENSES.txt -t $out/share/doc/rustgis/

    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "Fast free open-source GIS for mapping and analysing geospatial data (desktop + CLI)";
    homepage = "https://rustgis.app/";
    license = lib.licenses.asl20;
    mainProgram = "rustgis";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
