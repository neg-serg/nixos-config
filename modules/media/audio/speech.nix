{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.speech";
  systemdUser = config.lib.neg.systemdUser;
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
  eng = "/zero/ai/speech/engines"; # speech stack location (ZFS pool, main user-owned)
  # Inference only: nixpkgs builds piper with training extras (torch + triton,
  # ~3G) and Japanese dictionaries (~320M) by default; neither is used here.
  piper = pkgs.piper-tts.override {
    withTrain = false;
    withJapanese = false;
  };

  # Shared python for the thin FastAPI wrappers (piper-server.py / whisper-server.py).
  # Chatterbox uses its own pip venv (torch ROCm wheels) — see the setup script.
  serverPy = pkgs.python3.withPackages (ps: [
    ps.fastapi
    ps.uvicorn
    ps.pydantic
    ps.python-multipart # UploadFile parsing in whisper-server.py
  ]);

  whisperCpp = pkgs.whisper-cpp.override { vulkanSupport = true; }; # GPU STT via Vulkan (RADV), gfx1201

  # Chatterbox runs pip-installed torch ROCm wheels inside a venv; those wheels
  # are manylinux ELFs and need nixpkgs' libstdc++/libzstd (not on NixOS default
  # linker path). Declare the search path declaratively instead of hardcoding
  # store paths in chatterbox.env.
  #
  # The venv interpreter must stay on the *profile* path
  # (/run/current-system/sw/bin/python3.12): a store-path symlink (what uv/venv
  # create by default) is GC'ed with the next python312 update and the unit
  # then crash-loops with status=203/EXEC — repaired 2026-10-16 (relink
  # bin/python3.12 + pyvenv.cfg; backup kept as pyvenv.cfg.bak-20261016).
  # uv-managed pythons are generic ELFs NixOS refuses to run without patchelf.
  chatterboxLibPath = pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib # libstdc++.so.6, libgomp.so.1
    pkgs.zstd # libzstd.so.1
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [
      piper # CPU TTS fallback (piper-server on :8001) — note: pkgs.piper is a GTK mouse GUI!
      whisperCpp # GPU STT (whisper-cli, Vulkan backend — whisper-server on :8002)
      # Speech toolkit (ASR/TTS/VAD + speaker diarization) for local
      # experiments: the launcher builds it on first call. The sibling CLIs
      # (sherpa-onnx-offline, -denoiser, …) are one `nix shell
      # /etc/nixos#sherpa-onnx` away.
      (onDemand {
        name = "sherpa-onnx";
        attr = "sherpa-onnx";
      })
      pkgs.rocmPackages.rocm-smi # VRAM/GPU monitoring for the ROCm TTS stack (chatterbox)
      pkgs.ffmpeg # audio conversion for whisper-server (mp3/ogg → wav)
      pkgs.python312 # base interpreter for the chatterbox venv (keeps it GC-safe; torch cp312 wheels)
      pkgs.aubio # audio onset/beat/tempo analysis (aubioonset/aubiotrack CLIs) for music tools
    ];

    # User services (run as neg on login). Chatterbox needs the pip venv created
    # by /zero/ai/speech/engines/setup-chatterbox.sh first (torch ROCm wheels).
    systemd.user.services = {
      piper-tts = systemdUser.mkUserService {
        presets = [
          "defaultWanted"
          "restartOnFailure"
        ];
        description = "Piper TTS Server (OpenAI-compatible, CPU)";
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          RestartSec = 5;
          MemoryMax = "1G";
          Environment = "PATH=${piper}/bin:${pkgs.ffmpeg}/bin";
          ExecStart = "${serverPy}/bin/python ${eng}/piper-server.py --port 8001 --voices-dir ${eng}/voices";
        };
      };
      whisper-stt = systemdUser.mkUserService {
        presets = [
          "defaultWanted"
          "restartOnFailure"
        ];
        description = "Whisper STT Server (OpenAI-compatible, whisper.cpp Vulkan)";
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          RestartSec = 5;
          MemoryMax = "4G";
          Environment = "PATH=${pkgs.ffmpeg}/bin";
          ExecStart = "${serverPy}/bin/python ${eng}/whisper-server.py --port 8002 --host 127.0.0.1 --model ${eng}/voices/ggml-large-v3-turbo.bin --whisper-bin ${whisperCpp}/bin/whisper-cli";
        };
      };
      # On demand, never at login: the venv loads torch on the GPU and holds
      # ~3.2 GiB of VRAM for as long as the server runs, synthesising or not —
      # measured with `amdgpu_top -p` on 2026-11-02, the largest single consumer
      # on the 16 GiB card next to a 4K compositor and a browser, and a big part
      # of why a VRAM-hungry game took the GPU down that evening. Being enabled
      # paid that cost every session for a server used now and then; the cheap
      # parts of the stack (Piper, whisper.cpp) keep `defaultWanted`.
      # Start it when a voice is wanted: `systemctl --user start chatterbox-tts`.
      chatterbox-tts = systemdUser.mkUserService {
        presets = [
          "restartOnFailure"
        ];
        description = "Chatterbox TTS Server (OpenAI-compatible, ROCm GPU)";
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          WorkingDirectory = "${eng}/chatterbox-server";
          EnvironmentFile = "${eng}/config/chatterbox.env";
          Environment = "LD_LIBRARY_PATH=${chatterboxLibPath}"; # torch wheels need libstdc++/libzstd
          RestartSec = 10;
          MemoryMax = "16G";
          TimeoutStartSec = 300;
          ExecStart = "${eng}/.venv-chatterbox/bin/python server.py";
        };
      };
    };
  };
}
