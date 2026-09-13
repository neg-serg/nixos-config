runHook preInstall

# Place samples where SuperDirt expects them:
#   $out/share/Dirt-Samples/
# The Tidal startup script (~/.config/SuperCollider/superdirt_startup.scd)
# points ~dirt.loadSoundFiles at this path explicitly.
mkdir -p "$out/share/Dirt-Samples"

# Copy all sample directories (each is a sound name like "bd", "sn", "hh")
for dir in */; do
  # Skip non-sample files
  case "$dir" in
    Dirt-Samples.quark | README.md | .git*)
      continue
      ;;
  esac
  cp -r "$dir" "$out/share/Dirt-Samples/"
done

# Also copy the quark manifest so SC quark system can discover it
cp Dirt-Samples.quark "$out/share/Dirt-Samples/" 2> /dev/null || true

runHook postInstall
