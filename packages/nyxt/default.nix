{
  appimageTools,
  fetchurl,
  runCommand,
}: let
  pname = "nyxt4-bin";
  version = "4.0.0-pre-release-13";
  src = fetchurl {
    url = "https://github.com/atlas-engineer/nyxt/releases/download/${version}/Linux-Nyxt-x86_64.tar.gz";
    hash = "sha256-9kwgLVvnqXJnL/8jdY2jly/bS2XtgF9WBsDeoXNHX8M=";
  };
  appimage = runCommand "extract-nyxt" {} ''
    mkdir -p $out
    tar xf ${src} -C $out
    mv $out/Nyxt-x86_64.AppImage $out/${pname}.AppImage
  '';
in
  appimageTools.wrapType2 {
    inherit pname version;
    src = "${appimage}/${pname}.AppImage";
    extraPkgs = pkgs:
      with pkgs; [
        enchant
        # Common deps for GUI apps / Electron / WebKit
        gsettings-desktop-schemas
        glib
        gtk3
        cairo
        pango
        gdk-pixbuf
        at-spi2-atk
        at-spi2-core
        dbus
        libdrm
        libxkbcommon
        mesa
        nspr
        nss
        cups
        alsa-lib
        # GStreamer
        gst_all_1.gstreamer
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-bad
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-ugly
      ];
    meta.mainProgram = "nyxt4-bin";
  }
