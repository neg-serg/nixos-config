runHook preInstall

mkdir -p $out/bin $out/lib/midi2sheet
install -m 0644 @PY@ $out/lib/midi2sheet/split.py
install -m 0644 @PY_V2@ $out/lib/midi2sheet/patch_title.py
install -m 0755 @SH@ $out/lib/midi2sheet/midi2sheet.sh

makeWrapper $out/lib/midi2sheet/midi2sheet.sh $out/bin/midi2sheet \
  --prefix PATH : @COREUTILS@ \
  --set LIB $out/lib/midi2sheet

runHook postInstall
