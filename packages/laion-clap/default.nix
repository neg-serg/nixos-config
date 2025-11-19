{
  lib,
  fetchurl,
  python3Packages,
}: let
  pythonSitePackages = python3Packages.python.sitePackages;
  robertaVocab = fetchurl {
    url = "https://huggingface.co/roberta-base/resolve/main/vocab.json";
    hash = "sha256-nn9jwtFdZmtS4h0lDS5RO4fJtxPPpph6gu2J5eblBlU=";
  };
  robertaMerges = fetchurl {
    url = "https://huggingface.co/roberta-base/resolve/main/merges.txt";
    hash = "sha256-HOFmR3PFDz4MyIQmGak+3EYkUltyixiKngvjO3cmrcU=";
  };
  robertaTokenizerJson = fetchurl {
    url = "https://huggingface.co/roberta-base/resolve/main/tokenizer.json";
    hash = "sha256-hHu+q2F01mqIiY9ynVL6jTVfr+G+oQHPlg3UBFgd9w4=";
  };
  robertaTokenizerConfig = fetchurl {
    url = "https://huggingface.co/roberta-base/resolve/main/tokenizer_config.json";
    hash = "sha256-mU9GdUxb9AFPGqktNLE3QxnDprP3AhBc1bdCvq7NGM4=";
  };
  robertaSpecialTokens = ''    {
      "bos_token": "<s>",
      "eos_token": "</s>",
      "unk_token": "<unk>",
      "sep_token": "</s>",
      "pad_token": "<pad>",
      "cls_token": "<s>",
      "mask_token": "<mask>"
    }'';
  # Note: no local patching; tokenizer resources are vendored below.
in
  python3Packages.buildPythonPackage rec {
    pname = "laion_clap";
    version = "1.1.7";

    src = python3Packages.fetchPypi {
      inherit pname version;
      hash = "sha256-mrnFI2ueCUT2fWaF7yqcFIFOvRPA2GLH/gepu1ZgQ5c=";
    };

    pyproject = true;
    build-system = [python3Packages.setuptools];

    propagatedBuildInputs = with python3Packages; [
      numpy
      soundfile
      librosa
      torchlibrosa
      ftfy
      braceexpand
      webdataset
      wget
      wandb
      llvmlite
      scipy
      scikit-learn
      pandas
      h5py
      tqdm
      regex
      transformers
      progressbar
      torch
      torchaudio
      torchvision
    ];

    pythonRelaxDeps = ["numpy" "scipy" "pandas" "torch" "torchaudio" "torchvision"];

    postPatch = ''
          python3 <<'PY'
      from pathlib import Path
      import os

      hook = Path("src/laion_clap/hook.py")
      text = hook.read_text()
      if "from pathlib import Path" not in text:
          text = text.replace("import librosa\n", "import librosa\nfrom pathlib import Path\n", 1)
      text = text.replace(
          "RobertaTokenizer.from_pretrained('roberta-base')",
          "RobertaTokenizer.from_pretrained(Path(__file__).parent / 'roberta-base', local_files_only=True)",
      )
      text = text.replace(
          "            package_dir = os.path.dirname(os.path.realpath(__file__))\n            weight_file_name = download_names[model_id]\n            ckpt = os.path.join(package_dir, weight_file_name)\n            if os.path.exists(ckpt):\n                logging.info(f'The checkpoint is already downloaded')\n            else:\n                logging.info('Downloading laion_clap weight files...')\n                ckpt = wget.download(download_link + weight_file_name, os.path.dirname(ckpt))\n                logging.info('Download completed!')\n",
          "            cache_root = Path(os.environ.get('LAION_CLAP_CACHE') or os.environ.get('XDG_CACHE_HOME') or (Path.home() / '.cache')) / 'laion_clap'\n            cache_root.mkdir(parents=True, exist_ok=True)\n            weight_file_name = download_names[model_id]\n            ckpt = cache_root / weight_file_name\n            if ckpt.exists():\n                logging.info('The checkpoint is already cached')\n            else:\n                logging.info('Downloading laion_clap weight files...')\n                tmp_path = Path(wget.download(download_link + weight_file_name, str(cache_root)))\n                if tmp_path != ckpt:\n                    tmp_path.replace(ckpt)\n                logging.info('Download completed!')\n",
      )
      text = text.replace(
          "            ckpt = load_state_dict(ckpt, skip_params=True)\n            self.model.load_state_dict(ckpt)",
          "            ckpt = load_state_dict(ckpt, skip_params=True)\n            self.model.load_state_dict(ckpt, strict=False)",
      )
      hook.write_text(text)

      p = Path("src/laion_clap/training/data.py")
      data = p.read_text()
      if "TOKENIZER_DIR" not in data:
          data = data.replace(
              "from transformers import BartTokenizer\n",
              "from transformers import BartTokenizer\n\nTOKENIZER_DIR = Path(__file__).parent\n",
          )
      data = data.replace(
          "bert_tokenizer = BertTokenizer.from_pretrained(\"bert-base-uncased\")",
          "bert_tokenizer = None",
      )
      data = data.replace(
          "roberta_tokenizer = RobertaTokenizer.from_pretrained(\"roberta-base\")",
          "roberta_tokenizer = None",
      )
      data = data.replace(
          "bart_tokenizer = BartTokenizer.from_pretrained(\"facebook/bart-base\")",
          "bart_tokenizer = None",
      )
      data = data.replace(
          "elif tmodel == \"bert\":",
          "elif tmodel == \"bert\":\n        if bert_tokenizer is None:\n            raise RuntimeError(\"BERT tokenizer resources not packaged; set tmodel to 'roberta'\")",
      )
      data = data.replace(
          "elif tmodel == \"roberta\":",
          "elif tmodel == \"roberta\":\n        global roberta_tokenizer\n        if roberta_tokenizer is None:\n            roberta_tokenizer = RobertaTokenizer.from_pretrained(TOKENIZER_DIR / 'roberta-base', local_files_only=True)",
      )
      data = data.replace(
          "elif tmodel == \"bart\":",
          "elif tmodel == \"bart\":\n        if bart_tokenizer is None:\n            raise RuntimeError(\"BART tokenizer resources not packaged; set tmodel to 'roberta'\")",
      )
      p.write_text(data)
      PY
    '';

    postInstall = ''
          token_dir=$out/${pythonSitePackages}/laion_clap/roberta-base
          mkdir -p $token_dir
          cp ${robertaVocab} $token_dir/vocab.json
          cp ${robertaMerges} $token_dir/merges.txt
          cp ${robertaTokenizerJson} $token_dir/tokenizer.json
          cp ${robertaTokenizerConfig} $token_dir/tokenizer_config.json
          cat > $token_dir/special_tokens_map.json <<'TOKENS'
      ${robertaSpecialTokens}
      TOKENS
    '';

    doCheck = false;
    pythonImportsCheck = [];

    meta = {
      description = "Contrastive Language-Audio Pretraining model from LAION";
      homepage = "https://github.com/LAION-AI/CLAP";
      license = lib.licenses.asl20;
      maintainers = with lib.maintainers; [];
    };
  }
