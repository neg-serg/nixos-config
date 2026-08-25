{
  lib,
  pkgs,
  ...
}:

let
  # Python env for the hFT-Transformer runtime. Source torch (CPU-only build,
  # BSD license) — torch-bin is gated broken in this nixpkgs rev (cuda-bindings
  # 12.9.7 < 13.0.3) and would need global allowUnfree/config changes.
  pythonEnv = pkgs.python313.withPackages (ps: [
    ps.torch # PyTorch (CPU-only build) — hFT-Transformer inference
    ps.numpy # numeric array ops (mel feature computation)
    ps.scipy # resample_poly for the 44.1k -> 16k downmix
    ps.soundfile # wav/flac/ogg reading
    ps.mido # minimal MIDI file writer
  ]);

  hftSrc = pkgs.fetchFromGitHub {
    owner = "sony";
    repo = "hFT-Transformer";
    rev = "71a2ee06e9ced1ea24673c95ee0acded2fc98d04";
    sha256 = "0rpxd9dzr5pk8a9fb1w60jb2733s339934x5ls433fz9xhpsgbxa";
  };

  # Pretrained MAESTRO-V3 checkpoint (model_016_003.pkl + parameter.json),
  # official release from the repo above.
  checkpoint = pkgs.fetchurl {
    url = "https://github.com/sony/hFT-Transformer/releases/download/ismir2023/checkpoint.zip";
    sha256 = "sha256-uzyIdY5IAuaziBzLbceSdBf7Q/dpgN83OasrvEGNcMU=";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "midi-transcribe";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.unzip ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/midi-transcribe/hft/checkpoint/MAESTRO-V3

    # hFT model code + dataset config (training/eval/corpus scripts not shipped)
    cp -r ${hftSrc}/model $out/lib/midi-transcribe/hft/
    cp ${hftSrc}/corpus/config.json $out/lib/midi-transcribe/hft/corpus/config.json
    cp ${hftSrc}/LICENSE $out/lib/midi-transcribe/hft/LICENSE

    # torchaudio/pretty_midi are unused on the CPU path (numpy mel features,
    # mido writer); drop the imports so the vendored amt.py loads without them.
    sed -i '/^import torchaudio$/d' $out/lib/midi-transcribe/hft/model/amt.py
    sed -i '/^import pretty_midi$/d' $out/lib/midi-transcribe/hft/model/amt.py

    # checkpoint zip unpacks as checkpoint/MAESTRO-V3/... — flatten one level
    unzip -q ${checkpoint} -d $out/lib/midi-transcribe/hft/checkpoint
    mv $out/lib/midi-transcribe/hft/checkpoint/checkpoint/MAESTRO-V3/* \
       $out/lib/midi-transcribe/hft/checkpoint/MAESTRO-V3/
    rmdir $out/lib/midi-transcribe/hft/checkpoint/checkpoint/MAESTRO-V3 \
          $out/lib/midi-transcribe/hft/checkpoint/checkpoint 2>/dev/null || true

    install -m 0755 ${./transcribe.py} $out/lib/midi-transcribe/transcribe.py

    cat > $out/bin/midi-transcribe <<EOF
    #!${pkgs.bash}/bin/bash
    exec ${pythonEnv}/bin/python $out/lib/midi-transcribe/transcribe.py "$@"
    EOF
    chmod +x $out/bin/midi-transcribe

    runHook postInstall
  '';

  meta = with lib; {
    description = "Audio-to-MIDI transcription with Sony hFT-Transformer (ISMIR 2023, CPU)";
    homepage = "https://github.com/sony/hFT-Transformer";
    license = licenses.mit; # hFT-Transformer repo (Sony Group Corp)
    platforms = platforms.linux;
    mainProgram = "midi-transcribe";
  };
}
