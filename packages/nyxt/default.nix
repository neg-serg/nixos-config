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
    pkgs.enchant # Generic spell checking library
    # Common deps for GUI apps / Electron / WebKit
    pkgs.gsettings-desktop-schemas # Collection of GSettings schemas for settings shared by va...
    pkgs.glib # C library of programming buildings blocks
    pkgs.gtk3 # Multi-platform toolkit for creating graphical user interf...
    pkgs.cairo
    pkgs.pango # Library for laying out and rendering of text, with an emp...
    pkgs.gdk-pixbuf # Library for image loading and manipulation
    pkgs.at-spi2-atk
    pkgs.at-spi2-core
    pkgs.dbus # Simple interprocess messaging system
    pkgs.libdrm # Direct Rendering Manager library and headers
    pkgs.libxkbcommon # Library to handle keyboard descriptions
    pkgs.mesa # Open source 3D graphics library
    pkgs.nspr # Netscape Portable Runtime, a platform-neutral API for sys...
    pkgs.nss # Set of libraries for development of security-enabled clie...
    pkgs.cups # Standards-based printing system for UNIX
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
