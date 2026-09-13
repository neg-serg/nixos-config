runHook preInstall

# SuperCollider looks for extensions in a fixed layout:
#   $out/share/SuperCollider/extensions/<QuarkName>/
extdir="$out/share/SuperCollider/extensions/SuperDirtMixer"
mkdir -p "$extdir"

# Copy class files (the actual SC code)
cp -r classes "$extdir/"
# Copy synth definitions (SynthDef files)
cp -r synths "$extdir/"
# Copy help source
cp -r HelpSource "$extdir/"
# Copy UI assets (SVG icons for the EQ curve)
cp -r assets "$extdir/"
# Copy default presets (JSON, user-writable copy lives in the home dir)
cp -r presets "$extdir/"
# Copy TidalCycles pattern functions (SC-side helpers for the mixer)
cp -r tidal "$extdir/"
# Copy the quark manifest
cp SuperDirtMixer.quark "$extdir/"
cp LICENSE README.md "$extdir/" 2> /dev/null || true

runHook postInstall
