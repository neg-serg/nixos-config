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

  installPhase =
    builtins.replaceStrings
      [
        "@HFTSRC@"
        "@HFTSRC_V2@"
        "@HFTSRC_V3@"
        "@CHECKPOINT@"
        "@ROBUSTCHECKPOINT@"
        "@WHEELS@"
        "@SHIM@"
        "@PY@"
        "@BASH@"
        "@PYTHONENV@"
      ]
      [
        "${hftSrc}"
        "${hftSrc}"
        "${hftSrc}"
        "${checkpoint}"
        "${robustCheckpoint}"
        (builtins.concatStringsSep " " wheels)
        "${./shim}"
        "${./transcribe.py}"
        "${pkgs.bash}"
        "${pythonEnv}"
      ]
      (builtins.readFile ./install.sh);

  meta = with lib; {
    description = "Audio-to-MIDI transcription (CPU): RobustAMT default backend, Sony hFT-Transformer optional";
    homepage = "https://github.com/sony/hFT-Transformer";
    license = licenses.mit; # hFT-Transformer repo (Sony Group Corp)
    platforms = platforms.linux;
    mainProgram = "midi-transcribe";
  };
}
