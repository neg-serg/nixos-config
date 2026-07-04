{
  lib,
  stdenv,
  makeWrapper,
  skwd-src, # flake input source (github:liixini/skwd, flake=false)
  skwd-daemon, # pre-built daemon from flake input
  quickshell, # from nixpkgs (matches user's Qt version)
  qt6,
  matugen,
  ffmpeg,
  imagemagick,
  inotify-tools,
  curl,
  file,
  iwd,
  cava,
  nerd-fonts,
  roboto,
  roboto-mono,
  material-design-icons,
}:
let
  runtimeDeps = [
    skwd-daemon
    matugen
    ffmpeg
    imagemagick
    inotify-tools
    curl
    file
    iwd
    cava
  ];

  # Qt env vars matching user's quickshell wrapper, plus qtimageformats for skwd
  qtPluginPaths = lib.makeSearchPath qt6.qtbase.qtPluginPrefix [
    qt6.qtbase
    qt6.qt5compat
    qt6.qtwayland
    qt6.qtsvg
    qt6.qtmultimedia
    qt6.qtimageformats
  ];

  qtQmlPaths = lib.makeSearchPath qt6.qtbase.qtQmlPrefix [
    qt6.qt5compat
    qt6.qtdeclarative
    qt6.qtpositioning
    qt6.qtsvg
    qt6.qtmultimedia
    qt6.qtimageformats
  ];

  allRuntimeDeps = runtimeDeps ++ [ quickshell ];

  fonts = [
    nerd-fonts.symbols-only
    roboto
    roboto-mono
    material-design-icons
  ];

  # Helper: create a wrapped quickshell binary for a skwd component
  mkSkwdComponent =
    { name, extraData ? [ ] }:
    let
      componentDir = "$out/share/skwd/${name}";
    in
    ''
      mkdir -p $out/share/skwd/${name}
      cp -a ${skwd-src}/${name}/shell.qml $out/share/skwd/${name}/shell.qml
      cp -a ${skwd-src}/${name}/qml       $out/share/skwd/${name}/qml
      ${lib.optionalString (builtins.pathExists "${skwd-src}/${name}/data") ''
        cp -a ${skwd-src}/${name}/data      $out/share/skwd/${name}/data
      ''}
      ${lib.optionalString (builtins.pathExists "${skwd-src}/${name}/ext") ''
        cp -a ${skwd-src}/${name}/ext       $out/share/skwd/${name}/ext
      ''}
      makeWrapper ${lib.getExe quickshell} $out/bin/${name} \
        --prefix QT_PLUGIN_PATH : ${qtPluginPaths} \
        --prefix QML2_IMPORT_PATH : ${qtQmlPaths} \
        --prefix PATH : ${lib.makeBinPath allRuntimeDeps} \
        --set SKWD_INSTALL "$out/share/skwd" \
        --set SKWD_${lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] name)}_INSTALL "$out/share/skwd/${name}" \
        --set QT_QPA_PLATFORM wayland \
        --set QML_XHR_ALLOW_FILE_READ 1 \
        --add-flags "-p $out/share/skwd/${name}/shell.qml"
    '';
in
stdenv.mkDerivation {
  pname = "skwd";
  version = "unstable";
  src = skwd-src;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    ${mkSkwdComponent { name = "skwd-bar"; extraData = [ ]; }}
    ${mkSkwdComponent { name = "skwd-launch"; }}
    ${mkSkwdComponent { name = "skwd-music"; }}
    ${mkSkwdComponent { name = "skwd-notification"; }}
    ${mkSkwdComponent { name = "skwd-power"; }}
    ${mkSkwdComponent { name = "skwd-settings"; }}
    ${mkSkwdComponent { name = "skwd-switch"; }}

    # daemon CLI + service unit
    makeWrapper ${lib.getExe skwd-daemon} $out/bin/skwd \
      --prefix PATH : ${lib.makeBinPath allRuntimeDeps} \
      --set SKWD_INSTALL "$out/share/skwd"

    makeWrapper ${lib.getExe' skwd-daemon "skwd-daemon"} $out/bin/skwd-daemon \
      --prefix PATH : ${lib.makeBinPath allRuntimeDeps} \
      --set SKWD_INSTALL "$out/share/skwd"

    mkdir -p $out/lib/systemd/user
    substitute ${skwd-daemon}/lib/systemd/user/skwd-daemon.service \
      $out/lib/systemd/user/skwd-daemon.service \
      --replace-fail "${skwd-daemon}/bin/skwd-daemon" "$out/bin/skwd-daemon"

    install -Dm644 ${skwd-src}/data/config.json.example $out/share/skwd/data/config.json.example
    install -Dm644 ${skwd-src}/LICENSE $out/share/licenses/skwd/LICENSE
    install -Dm644 ${skwd-src}/data/mdi-icons.json $out/share/skwd/data/mdi-icons.json

    mkdir -p $out/share/fonts
    for font in ${lib.concatMapStringsSep " " toString fonts}; do
      if [ -d "$font/share/fonts" ]; then
        for f in $(find "$font/share/fonts" -type f); do
          ln -sf "$f" "$out/share/fonts/$(basename $f)"
        done
      fi
    done
  '';

  meta = with lib; {
    description = "Quickshell-based desktop shell suite (bar, launcher, music, notifications, settings, switcher) backed by skwd-daemon";
    homepage = "https://github.com/liixini/skwd";
    license = licenses.mit;
    mainProgram = "skwd-bar";
    platforms = platforms.linux;
  };
}
