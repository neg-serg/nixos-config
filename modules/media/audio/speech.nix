{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.speech";
  systemdUser = config.lib.neg.systemdUser;
  onDemand = config.lib.neg.onDemand pkgs;
  eng = "/zero/ai/speech/engines"; # speech stack location (ZFS pool, main user-owned)
  # whisper.cpp and its python env are NOT in the system closure: the
  # `speech-stack` flake attr (see packages/flake/custom-packages.nix) merges
  # it with ffmpeg, and this wrapper materialises that root on the first
  # service start (~/.local/state/nix-apps/speech-stack), puts it on PATH and
  # starts the whisper server. The engine itself lives on /zero.
  speechStack = pkgs.writeShellScriptBin "speech-stack" ''
    set -eu
    root="$HOME/.local/state/nix-apps/speech-stack"
    if [ ! -e "$root" ]; then
      mkdir -p "$(dirname "$root")"
      rm -f "$root"
      out=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths "git+file:///etc/nixos#speech-stack")
      ${pkgs.nix}/bin/nix-store --add-root "$root" --indirect --realise "$out" >/dev/null
    fi
    export PATH="$root/bin''${PATH:+:$PATH}"
    case "''${1:-}" in
      whisper)
        shift
        exec python ${eng}/whisper-server.py \
          --port 8002 --host 127.0.0.1 \
          --model ${eng}/voices/ggml-large-v3-turbo.bin \
          --whisper-bin "$root/bin/whisper-cli" "$@"
        ;;
      *)
        echo "usage: speech-stack whisper" >&2
        exit 2
        ;;
    esac
  '';

in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [
      # whisper.cpp (GPU STT on :8002) is built from the on-demand speech
      # stack by its unit, not installed here.
      #
      # Speech toolkit (ASR/TTS/VAD + speaker diarization) for local
      # experiments: the launcher builds it on first call. The sibling CLIs
      # (sherpa-onnx-offline, -denoiser, …) are one `nix shell
      # /etc/nixos#sherpa-onnx` away.
      (onDemand {
        name = "sherpa-onnx";
        attr = "sherpa-onnx";
      })
      pkgs.aubio # audio onset/beat/tempo analysis (aubioonset/aubiotrack CLIs) for music tools
      speechStack # manual entry point: speech-stack whisper (materialises the stack)
    ];

    # User service (runs as neg on login): speech recognition only. The TTS
    # half (Piper, Chatterbox) and its models were removed on 2026-11-20.
    systemd.user.services = {
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
          ExecStart = "${speechStack}/bin/speech-stack whisper";
        };
      };
    };
  };
}
