_inputs: _final: prev:
let
  # Two levels of trimming, both applied only to packages whose `out` is
  # executed here rather than linked against:
  #
  #   trimLibs — static archives. Nothing in the closure links them at build
  #   time because these are leaves: kanata alone ships a 45 MiB
  #   libkanata_state_machine.a, inotify-tools 10 MiB.
  #
  #   trimDocs — doc/info/man trees. Headers are deliberately left alone: some
  #   packages in nixpkgs install their headers into `out` (libvirt does), and
  #   other packages in the closure compile against them, so dropping
  #   $out/include breaks their build — libvirt-glib fails exactly this way.
  trimLibs =
    pkg:
    pkg.overrideAttrs (old: {
      postFixup = (old.postFixup or "") + ''
        find $out -name '*.a' -delete
      '';
    });
  trimDocs =
    pkg:
    pkg.overrideAttrs (old: {
      postFixup = (old.postFixup or "") + ''
        rm -rf $out/share/doc $out/share/info $out/share/man $out/man
      '';
    });
in
{
  kanata = trimLibs prev.kanata;
  inotify-tools = trimLibs prev.inotify-tools;
  kyotocabinet = trimLibs prev.kyotocabinet;

  kitty = trimDocs prev.kitty;
  gdb = trimDocs prev.gdb;
  neomutt = trimDocs prev.neomutt;
  libvirt = trimDocs prev.libvirt;
  spice-gtk = trimDocs prev.spice-gtk;
  freerdp = trimDocs prev.freerdp;
}
