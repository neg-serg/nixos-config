runHook preInstall

# SuperCollider looks for extensions in a fixed layout:
#   $out/share/SuperCollider/extensions/<QuarkName>/
extdir="$out/share/SuperCollider/extensions/SuperDirt"
mkdir -p "$extdir"

# Copy class files (the actual SC code)
cp -r classes "$extdir/"
# Copy synth definitions (SynthDef files)
cp -r synths "$extdir/"
# Copy help source
cp -r HelpSource "$extdir/"
# Copy library support scripts
cp -r library "$extdir/"
# Copy the quark manifest
cp SuperDirt.quark "$extdir/"
cp LICENSE README.md "$extdir/" 2> /dev/null || true

runHook postInstall
