{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.speech";
  eng = "/zero/ai/speech/engines"; # speech stack location (ZFS pool, main user-owned)

  # Shared python for the thin FastAPI wrappers (piper-server.py / whisper-server.py).
  # Chatterbox uses its own pip venv (torch ROCm wheels) — see the setup script.
  serverPy = pkgs.python3.withPackages (ps: [
    ps.fastapi
    ps.uvicorn
    ps.pydantic
    ps.python-multipart # UploadFile parsing in whisper-server.py
  ]);

  whisperCpp = pkgs.whisper-cpp.override { vulkanSupport = true; }; # GPU STT via Vulkan (RADV), gfx1201
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [
      pkgs.piper # CPU TTS fallback (piper-server on :8001)
      whisperCpp # GPU STT (whisper-cli, Vulkan backend — whisper-server on :8002)
      pkgs.rocmPackages.rocm-smi # VRAM/GPU monitoring for the ROCm TTS stack (chatterbox)
      pkgs.ffmpeg # audio conversion for whisper-server (mp3/ogg → wav)
    ];

    # User services (run as neg on login). Chatterbox needs the pip venv created
    # by /zero/ai/speech/engines/setup-chatterbox.sh first (torch ROCm wheels).
    systemd.user.services = {
      piper-tts = {
        description = "Piper TTS Server (OpenAI-compatible, CPU)";
        after = [ "network.target" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = 5;
          MemoryMax = "1G";
          Environment = "PATH=${pkgs.piper}/bin:${pkgs.ffmpeg}/bin";
          ExecStart = "${serverPy}/bin/python ${eng}/piper-server.py --port 8001 --voices-dir ${eng}/voices";
        };
      };
      whisper-stt = {
        description = "Whisper STT Server (OpenAI-compatible, whisper.cpp Vulkan)";
        after = [ "network.target" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = 5;
          MemoryMax = "4G";
          Environment = "PATH=${pkgs.ffmpeg}/bin";
          ExecStart = "${serverPy}/bin/python ${eng}/whisper-server.py --port 8002 --host 127.0.0.1 --model ${eng}/voices/ggml-large-v3-turbo.bin --whisper-bin ${whisperCpp}/bin/whisper-cli";
        };
      };
      chatterbox-tts = {
        description = "Chatterbox TTS Server (OpenAI-compatible, ROCm GPU)";
        after = [ "network.target" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          WorkingDirectory = "${eng}/chatterbox-server";
          EnvironmentFile = "${eng}/config/chatterbox.env";
          Restart = "on-failure";
          RestartSec = 10;
          MemoryMax = "16G";
          TimeoutStartSec = 300;
          ExecStart = "${eng}/.venv-chatterbox/bin/python server.py";
        };
      };
    };
  };
}
