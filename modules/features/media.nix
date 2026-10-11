{ lib, mkBool, ... }:
{
  options.features.media = {
    aiUpscale = {
      enable = mkBool "enable AI upscaling integration for video (mpv)" false;
    };
    audio = {
      core.enable = mkBool "enable audio core (PipeWire routing tools)" true;
      apps.enable = mkBool "enable audio apps (players, tools)" true;
      creation.enable = mkBool "enable audio creation stack (DAW, synths)" true;
      mpd.enable = mkBool "enable MPD stack (mpd, clients, mpdris2)" true;
      # Sola MPD: browser MPD client (Node backend + React UI on loopback) aimed
      # at large libraries — flexible browsing, search and queue editing.
      solaMpd = {
        enable = mkBool "enable Sola MPD (browser MPD client: backend + web UI)" false;
        port = lib.mkOption {
          type = lib.types.port;
          default = 3010; # 3000 is taken by another local service on trantor
          description = "Loopback port the Sola MPD backend listens on.";
        };
      };
      # LAN audio access: MPD binds to all interfaces, PipeWire exposes a
      # Pulse-compatible TCP server (port 4713) and an RTP multicast sink.
      lanAccess = {
        enable = mkBool "LAN audio access (MPD on all interfaces, PipeWire Pulse TCP 4713, RTP sink)" false;
        rtp = {
          interface = lib.mkOption {
            type = lib.types.str;
            default = "net1";
            description = "Network interface used by the PipeWire RTP sink for multicast output.";
          };
        };
      };
      cider.enable = mkBool "enable Cider (Apple Music client)" false;
      spicetify.enable = mkBool "enable Spicetify (Spotify customization)" false;
      beets = {
        enable = mkBool "enable Beets music library manager" true;
        mode = lib.mkOption {
          type = lib.types.enum [
            "native"
            "distrobox"
          ];
          default = "distrobox";
          description = "Beets runtime mode: native (Nixpkgs) or distrobox (CachyOS container)";
        };
      };
      speech.enable = mkBool "enable local speech stack (Chatterbox TTS :8300, Piper TTS :8001, whisper.cpp STT :8002)" false;
      # Music tagging and embeddings on the local music-AI venv:
      # music-embed (MERT embeddings), music-tags (CLAP zero-shot tags),
      # music-index / music-similar (similarity search over the library).
      # Installing them starts nothing; models are fetched on first use into
      # hfHome, and the wrappers run on a nix interpreter (GC-rooted) with the
      # venv's site-packages on PYTHONPATH.
      musicTagging = {
        enable = mkBool "enable music tagging/embedding wrappers (music-embed, music-tags, music-index)" true;
        embedModel = lib.mkOption {
          type = lib.types.str;
          default = "m-a-p/MERT-v1-95M";
          description = ''
            HuggingFace music embedding model. Measured on a same-track probe
            (10 albums): MERT-v1-95M rank1 0.50 / +0.025 margin at 1.5 s per
            track and 1.4 GiB; MERT-v2-30s rank1 0.65 / +0.046 at 2.0 s and
            3.2 GiB. The pooled layer is resolved per model (v1 -> -2,
            v2 -> -1) and recorded in the index signature.
          '';
        };
        hfHome = lib.mkOption {
          type = lib.types.str;
          default = "/zero/ai/music-ai/hf";
          description = "HuggingFace cache directory for the tagging/embedding models.";
        };
        mtgVenv = lib.mkOption {
          type = lib.types.str;
          default = "/zero/ai/music-ai/venv-mtg";
          description = ''
            venv with essentia-tensorflow for the trained MTG tagger
            (music-mtg-tags: Discogs-400 styles, Jamendo mood/theme and
            instrument heads). Filled by scripts/dev/music-mtg-setup.sh; the
            shared venv-analysis keeps its plain essentia build untouched.
          '';
        };
        mtgModels = lib.mkOption {
          type = lib.types.str;
          default = "/zero/ai/music-ai/mtg-models";
          description = ''
            EffNet-Discogs backbone and head models for music-mtg-tags, fetched
            by scripts/dev/music-mtg-models.sh (~25 MB, sha256-pinned mirrors).
          '';
        };
        # Opt-in background refresh: a systemd user timer re-runs the
        # incremental indexer so new albums get embedded without a manual
        # hours-long pass. Off by default; a host flips autoIndex.enable.
        autoIndex = {
          enable = mkBool "weekly background refresh of the music similarity index (systemd user timer)" false;
          onCalendar = lib.mkOption {
            type = lib.types.str;
            default = "Sun 04:00";
            description = "systemd calendar expression for the automatic music-index refresh.";
          };
          limit = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Embed at most the first N tracks per run (0 = no limit); passed to music-index as --limit.";
          };
        };
      };
      # MPD voice client (mpd-voice): one utterance -> local speech recognition
      # -> MPD command -> spoken confirmation. Installing it starts nothing and
      # touches no microphone: the CLI is inert until it is run (or bound to a
      # key), and it also has a text mode that needs no audio at all.
      mpdVoice = {
        enable = mkBool "enable MPD voice client (mpd-voice CLI + its config file)" true;
        language = lib.mkOption {
          type = lib.types.enum [
            "ru"
            "en"
          ];
          default = "ru";
          description = "Reply language and default speech recognition language.";
        };
        wakeWord = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Keyword required by `mpd-voice listen` (empty = every utterance is
            executed, which is what push-to-talk wants).
          '';
        };
        stt = lib.mkOption {
          type = lib.types.enum [
            "auto"
            "http"
            "cli"
            "cmd"
            "none"
          ];
          default = "auto";
          description = ''
            Speech recognition backend: auto probes the HTTP server below,
            then falls back to whisper-cli.
          '';
        };
        sttUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:8002";
          description = "Base URL of an OpenAI-compatible STT server (/v1/audio/transcriptions).";
        };
        tts = lib.mkOption {
          type = lib.types.enum [
            "auto"
            "http"
            "cmd"
            "none"
          ];
          default = "auto";
          description = ''
            Speech synthesis backend: auto probes the HTTP server below, then
            falls back to spd-say / espeak-ng.
          '';
        };
        ttsUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:8001";
          description = "Base URL of an OpenAI-compatible TTS server (/v1/audio/speech).";
        };
      };
    };
    photo.enable = mkBool "enable photography workflow (darktable, rawtherapee, testdisk)" false;
    webcam.enable = mkBool "enable virtual webcam support (v4l2loopback)" false;
  };
}
