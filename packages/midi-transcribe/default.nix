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

  # RobustAMT (Drew Edwards, CC-BY-4.0): bytedance high-resolution architecture
  # retrained with data augmentation — best measured accuracy + sustain pedal.
  robustCheckpoint = pkgs.fetchurl {
    url = "https://zenodo.org/api/records/10610212/files/high_resolution_MAESTRO_augmentations.pth/content";
    sha256 = "sha256-sg9yBTq8FbePaJsqiwTAoGUpyEZuiYuRWAOh2qIBG54=";
  };

  # Pure-python wheels vendored at build time (not in nixpkgs):
  # torchlibrosa (torch-based mel features), piano-transcription-inference
  # (RobustAMT runner), audioread + mir_eval (its runtime imports).
  wheels = [
    (pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/3e/af/ccf007edf442c3c0cd3a98be2c82bc99edc957c04436a759b6e1e01077e0/torchlibrosa-0.1.0-py3-none-any.whl";
      sha256 = "sha256-ibZf0ouDPOtrx0o9DYfikk3cWoRdCiRrGUlSpOEqOMs=";
    })
    (pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/a0/64/2360ab1eecf4c01a6c5d1bfb308f08a196236a559bcc135ca203e6742a5b/piano_transcription_inference-0.0.6-py3-none-any.whl";
      sha256 = "sha256-ZDSCALcAoO55KqYjhoA/sqY443izg1uafM/0cB8GEvU=";
    })
    (pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/7e/16/fbe8e1e185a45042f7cd3a282def5bb8d95bb69ab9e9ef6a5368aa17e426/audioread-3.1.0-py3-none-any.whl";
      sha256 = "sha256-sw0d9sXT3l3O8PsOJW9uoXvc9fl5QI3wKX2KQI4pcbQ=";
    })
    (pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/1b/5a/69ce896a32ebc8c75deae00b1fba9837567405fa6ef37b377f2e85b856ae/mir_eval-0.8.2-py3-none-any.whl";
      sha256 = "sha256-EUzaM9jhdAjBcFmOCzbtDXH/Si/ujq+eFltY7PHIcXA=";
    })
  ];
in
pkgs.stdenv.mkDerivation {
  pname = "midi-transcribe";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.unzip ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/midi-transcribe/hft/corpus \
      $out/lib/midi-transcribe/hft/checkpoint/MAESTRO-V3

    # hFT model code + dataset config (training/eval/corpus scripts not shipped)
    cp -r ${hftSrc}/model $out/lib/midi-transcribe/hft/
    # store source is read-only; sed -i needs a writable tree
    chmod -R u+w $out/lib/midi-transcribe/hft/model
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

    # RobustAMT checkpoint + vendored wheels (unpacked dirs go on sys.path)
    mkdir -p $out/lib/midi-transcribe/robust $out/lib/midi-transcribe/vendor
    cp ${robustCheckpoint} $out/lib/midi-transcribe/robust/high_resolution_MAESTRO_augmentations.pth
    for w in ${builtins.concatStringsSep " " wheels}; do
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
    cp -r ${./shim} $out/lib/midi-transcribe/shim

    install -m 0755 ${./transcribe.py} $out/lib/midi-transcribe/transcribe.py

    cat > $out/bin/midi-transcribe <<EOF
    #!${pkgs.bash}/bin/bash
    # \$@ escaped: stdenv evals installPhase inside runPhase (\$@ = phase name),
    # a bare "$@" would bake the literal phase name into the wrapper.
    exec ${pythonEnv}/bin/python $out/lib/midi-transcribe/transcribe.py "\$@"
    EOF
    chmod +x $out/bin/midi-transcribe

    runHook postInstall
  '';

  meta = with lib; {
    description = "Audio-to-MIDI transcription (CPU): RobustAMT default backend, Sony hFT-Transformer optional";
    homepage = "https://github.com/sony/hFT-Transformer";
    license = licenses.mit; # hFT-Transformer repo (Sony Group Corp)
    platforms = platforms.linux;
    mainProgram = "midi-transcribe";
  };
}
