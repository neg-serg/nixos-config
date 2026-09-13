runHook preInstall

mkdir -p $out/bin $out/lib/midi-transcribe/hft/corpus \
  $out/lib/midi-transcribe/hft/checkpoint/MAESTRO-V3

# hFT model code + dataset config (training/eval/corpus scripts not shipped)
cp -r @HFTSRC@/model $out/lib/midi-transcribe/hft/
# store source is read-only; sed -i needs a writable tree
chmod -R u+w $out/lib/midi-transcribe/hft/model
cp @HFTSRC_V2@/corpus/config.json $out/lib/midi-transcribe/hft/corpus/config.json
cp @HFTSRC_V3@/LICENSE $out/lib/midi-transcribe/hft/LICENSE

# torchaudio/pretty_midi are unused on the CPU path (numpy mel features,
# mido writer); drop the imports so the vendored amt.py loads without them.
sed -i '/^import torchaudio$/d' $out/lib/midi-transcribe/hft/model/amt.py
sed -i '/^import pretty_midi$/d' $out/lib/midi-transcribe/hft/model/amt.py

# checkpoint zip unpacks as checkpoint/MAESTRO-V3/... — flatten one level
unzip -q @CHECKPOINT@ -d $out/lib/midi-transcribe/hft/checkpoint
mv $out/lib/midi-transcribe/hft/checkpoint/checkpoint/MAESTRO-V3/* \
  $out/lib/midi-transcribe/hft/checkpoint/MAESTRO-V3/
rmdir $out/lib/midi-transcribe/hft/checkpoint/checkpoint/MAESTRO-V3 \
  $out/lib/midi-transcribe/hft/checkpoint/checkpoint 2> /dev/null || true

# RobustAMT checkpoint + vendored wheels (unpacked dirs go on sys.path)
mkdir -p $out/lib/midi-transcribe/robust $out/lib/midi-transcribe/vendor
cp @ROBUSTCHECKPOINT@ $out/lib/midi-transcribe/robust/high_resolution_MAESTRO_augmentations.pth
for w in @WHEELS@; do
  unzip -q "$w" -d $out/lib/midi-transcribe/vendor
done
# dead import in the vendored wheel (matplotlib only for the repo's own
# plotting); not in the python env, so drop it
sed -i '/^import matplotlib.pyplot as plt$/d' \
  $out/lib/midi-transcribe/vendor/piano_transcription_inference/models.py
# PyTorch >= 2.6 defaults torch.load to weights_only=True, which rejects
# this legacy checkpoint (numpy globals); checkpoint is hash-pinned, so
# full unpickling is safe
sed -i 's/torch.load(checkpoint_path, map_location=device)/torch.load(checkpoint_path, map_location=device, weights_only=False)/' \
  $out/lib/midi-transcribe/vendor/piano_transcription_inference/inference.py
# bytedance's 160 MB size heuristic is for its own download; our pinned
# checkpoint is 104 MB, so drop the size clause to skip the re-download
sed -i 's/if not os.path.exists(checkpoint_path) or os.path.getsize(checkpoint_path) < 1.6e8:/if not os.path.exists(checkpoint_path):/' \
  $out/lib/midi-transcribe/vendor/piano_transcription_inference/inference.py
cp -r @SHIM@ $out/lib/midi-transcribe/shim

install -m 0755 @PY@ $out/lib/midi-transcribe/transcribe.py

cat > $out/bin/midi-transcribe << EOF
#!@BASH@/bin/bash
# \$@ escaped: stdenv evals installPhase inside runPhase (\$@ = phase name),
# a bare "$@" would bake the literal phase name into the wrapper.
exec @PYTHONENV@/bin/python $out/lib/midi-transcribe/transcribe.py "\$@"
EOF
chmod +x $out/bin/midi-transcribe

runHook postInstall
