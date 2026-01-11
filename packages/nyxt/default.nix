{
  appimageTools,
  fetchurl,
  runCommand,
}:
let
  pname = "nyxt4-bin";
  version = "4.0.0-pre-release-13";
  src = fetchurl {
    url = "https://github.com/atlas-engineer/nyxt/releases/download/${version}/Linux-Nyxt-x86_64.tar.gz";
    hash = "sha256-9kwgLVvnqXJnL/8jdY2jly/bS2XtgF9WBsDeoXNHX8M=";
  };
  appimage = runCommand "extract-nyxt" { } ''
    mkdir -p $out
    tar xf ${src} -C $out
    mv $out/Nyxt-x86_64.AppImage $out/${pname}.AppImage
  '';
in
appimageTools.wrapType2 {
  inherit pname version;
  src = "${appimage}/${pname}.AppImage";
  extraPkgs = pkgs: [
    pkgs.enchant
    # Common deps for GUI apps / Electron / WebKit
    pkgs.gsettings-desktop-schemas
    pkgs.glib
    pkgs.gtk3
    pkgs.cairo
    pkgs.pango
    pkgs.gdk-pixbuf
    pkgs.at-spi2-atk
    pkgs.at-spi2-core
    pkgs.dbus
    pkgs.libdrm
    pkgs.libxkbcommon
    pkgs.mesa
    pkgs.nspr
    pkgs.nss
    pkgs.cups
    pkgs.alsa-lib
    # GStreamer
    pkgs.gst_all_1.gstreamer
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-bad
    pkgs.gst_all_1.gst-plugins-good
    pkgs.gst_all_1.gst-plugins-ugly
  ];
  meta.mainProgram = "nyxt4-bin";
}
