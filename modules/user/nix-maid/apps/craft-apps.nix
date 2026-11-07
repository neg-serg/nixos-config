##
# Module: apps/craft-apps
# Purpose: the ArtCraft suite as on-demand launchers — VectorCraft (vector
# illustration), FigCraft (interface design), SoundCraft (DAW), DeckCraft
# (presentations), GridCraft (spreadsheets) and SolidCraft (parametric 3D CAD).
#
# Every app is a large egui/wgpu Rust workspace (~100–150 MB of binary each), so
# none of it belongs in a system generation: lib/on-demand-app.nix builds
# `.#<app>` on first launch and GC-roots it under ~/.local/state/nix-apps, the
# same shape WordCraft and Craft Anything use. A GUI launcher and its `-cli`
# companion share one root (the CLI execs the same store path), so the second
# binary costs no extra build.
#
# The desktop entries are shipped here instead of being taken from the package:
# a package's own share/ tree lives inside the on-demand root and is therefore
# not on the system XDG_DATA_DIRS. The icon is addressed under $HOME for the
# same reason — pointing `icon` at the store path would pull the whole closure
# into system-path, the one thing the launcher avoids. Consequence: the entry
# shows its real icon only after the app has been built once.
#
# The MIME lists below mirror each app's upstream packaging/linux desktop file.
# They widen the "Open with" choice; the default handler per type stays in
# modules/user/nix-maid/gui/xdg.nix, so nothing here changes what a
# double-clicked .xlsx or .pptx opens by default.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "apps.craftApps";

  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };

  # Where lib/on-demand-app.nix registers the per-app GC root on first launch.
  appRoot = "${config.lib.neg.homeDir}/.local/state/nix-apps";

  apps = [
    {
      attr = "vectorcraft";
      appId = "ai.storyteller.vectorcraft";
      desktopName = "VectorCraft";
      genericName = "Vector Graphics Editor";
      comment = "Draw and edit vector illustrations, SVG and PDF";
      exec = "vectorcraft %F";
      categories = [
        "Graphics"
        "2DGraphics"
        "VectorGraphics"
      ];
      keywords = [
        "vector"
        "illustration"
        "svg"
        "pdf"
        "drawing"
        "bezier"
      ];
      mimeTypes = [
        "image/svg+xml"
        "application/pdf"
        "application/x-vectorcraft"
        "image/svg+xml-compressed"
        "application/illustrator"
        "application/x-ai-template"
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/tiff"
        "image/bmp"
        "application/x-vectorcraft-template"
        "image/vnd.dxf"
        "image/emf"
        "image/wmf"
        "image/x-eps"
        "application/x-affinity"
      ];
    }
    {
      attr = "figcraft";
      appId = "ai.storyteller.figcraft";
      desktopName = "FigCraft";
      genericName = "Interface Design Tool";
      comment = "Design and prototype user interfaces";
      exec = "figcraft %U";
      categories = [
        "Graphics"
        "2DGraphics"
        "VectorGraphics"
        "X-Design"
      ];
      keywords = [
        "design"
        "interface"
        "ui"
        "ux"
        "prototype"
        "wireframe"
        "mockup"
        "vector"
        "layout"
        "components"
      ];
      mimeTypes = [
        "application/x-figcraft"
        "image/svg+xml"
        "image/png"
        "image/jpeg"
        "application/x-sketch"
        "x-scheme-handler/figcraft"
      ];
    }
    {
      attr = "soundcraft";
      appId = "ai.storyteller.soundcraft";
      desktopName = "SoundCraft";
      genericName = "Digital Audio Workstation";
      comment = "Record, edit and mix audio and MIDI";
      exec = "soundcraft %F";
      categories = [
        "AudioVideo"
        "Audio"
        "Midi"
        "Mixer"
        "Sequencer"
        "Recorder"
      ];
      keywords = [
        "daw"
        "audio"
        "mixer"
        "recording"
        "multitrack"
        "midi"
        "editor"
        "music"
      ];
      mimeTypes = [
        "application/x-soundcraft-session"
        "audio/x-wav"
        "audio/wav"
        "audio/vnd.wave"
        "audio/x-aiff"
        "audio/aiff"
        "audio/flac"
        "audio/x-flac"
        "audio/mpeg"
        "audio/midi"
        "audio/x-midi"
      ];
    }
    {
      attr = "deckcraft";
      appId = "ai.storyteller.deckcraft";
      desktopName = "DeckCraft";
      genericName = "Presentation";
      comment = "Create and present slide decks";
      exec = "deckcraft %F";
      categories = [
        "Office"
        "Presentation"
      ];
      keywords = [
        "presentation"
        "slides"
        "slide show"
        "deck"
        "pptx"
        "keynote"
        "powerpoint"
      ];
      mimeTypes = [
        "application/x-deckcraft"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "application/vnd.openxmlformats-officedocument.presentationml.template"
        "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
      ];
    }
    {
      attr = "gridcraft";
      appId = "ai.storyteller.gridcraft";
      desktopName = "GridCraft";
      genericName = "Spreadsheet";
      comment = "Calculate, analyse and chart data in workbooks";
      exec = "gridcraft %F";
      categories = [
        "Office"
        "Spreadsheet"
      ];
      keywords = [
        "spreadsheet"
        "workbook"
        "sheet"
        "table"
        "formula"
        "chart"
        "pivot"
        "xlsx"
        "xlsb"
        "ods"
        "csv"
        "tsv"
        "excel"
      ];
      mimeTypes = [
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        "application/vnd.ms-excel.sheet.macroEnabled.12"
        "application/vnd.ms-excel.sheet.binary.macroEnabled.12"
        "application/vnd.oasis.opendocument.spreadsheet"
        "text/csv"
        "text/tab-separated-values"
      ];
    }
    {
      attr = "solidcraft";
      appId = "io.tangencylabs.solidcraft";
      desktopName = "SolidCraft";
      genericName = "3D CAD";
      comment = "Parametric 3D CAD: sketch, constrain, extrude, and change a parameter to rebuild";
      exec = "solidcraft %f";
      categories = [
        "Graphics"
        "3DGraphics"
        "Engineering"
      ];
      keywords = [
        "cad"
        "3d"
        "parametric"
        "sketch"
        "step"
        "stl"
        "modelling"
        "modeling"
      ];
      mimeTypes = [
        "application/x-solidcraft"
        "model/step"
        "model/iges"
        "model/stl"
        "model/3mf"
      ];
    }
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.concatMap (app: [
      (onDemand {
        name = app.attr;
        attr = app.attr;
      }) # ${app.desktopName} desktop app, built on first launch
      (onDemand {
        name = "${app.attr}-cli";
        attr = app.attr;
        binary = "${app.attr}-cli";
      }) # ${app.desktopName}'s headless CLI, same on-demand root
      (pkgs.makeDesktopItem {
        name = app.appId;
        inherit (app)
          desktopName
          genericName
          comment
          exec
          categories
          keywords
          mimeTypes
          ;
        icon = "${appRoot}/${app.attr}/share/icons/hicolor/256x256/apps/${app.appId}.png";
        tryExec = app.attr;
        terminal = false;
        startupNotify = true;
        startupWMClass = app.appId;
      })
    ]) apps;
  };
}
