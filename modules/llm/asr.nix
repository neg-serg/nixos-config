##
# Module: llm/asr
# Purpose: Russian-first speech recognition through sherpa-onnx — GigaAM-v3
# (MIT, ru/en) and Parakeet-TDT-0.6B-v3 (CC-BY-4.0, 25 European languages).
#
# Both models run on the CPU through the sherpa-onnx runtime, so they neither
# take VRAM from the chat stack nor need ROCm/torch: GigaAM transcribes a
# 5.7 s clip in ~0.15 s, Parakeet in ~0.27 s on 2 threads (measured
# 2026-11-05). Models live on /zero and are downloaded manually, like the
# llama GGUFs.
#
# The binaries are wrappers around an on-demand launcher: the first call
# builds sherpa-onnx and roots it under ~/.local/state/nix-apps, later calls
# exec the rooted binary. `gigaam-asr file.wav` / `parakeet-asr file.wav`
# print the JSON record sherpa-onnx emits (text, tokens, timestamps).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
  modelDir = "/zero/ai/asr";

  sherpa = onDemand {
    name = "sherpa-onnx-offline";
    attr = "sherpa-onnx";
    binary = "sherpa-onnx-offline";
  };

  # Flags go on one line: a trailing backslash-newline before `"$@"` would end
  # the exec command and swallow the file arguments.
  mkAsr =
    name: flags:
    pkgs.writeShellScriptBin name ''
      exec ${sherpa}/bin/sherpa-onnx-offline ${lib.concatStringsSep " " flags} "$@"
    '';
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [
      sherpa # sherpa-onnx runtime for the ASR models below, built on first use
      (mkAsr "gigaam-asr" [
        "--tokens=${modelDir}/gigaam-v3/tokens.txt"
        "--encoder=${modelDir}/gigaam-v3/encoder.int8.onnx"
        "--decoder=${modelDir}/gigaam-v3/decoder.onnx"
        "--joiner=${modelDir}/gigaam-v3/joiner.onnx"
      ]) # Russian ASR (GigaAM-v3, MIT)
      (mkAsr "parakeet-asr" [
        "--tokens=${modelDir}/parakeet-v3/tokens.txt"
        "--encoder=${modelDir}/parakeet-v3/encoder.int8.onnx"
        "--decoder=${modelDir}/parakeet-v3/decoder.int8.onnx"
        "--joiner=${modelDir}/parakeet-v3/joiner.int8.onnx"
      ]) # fast multilingual ASR (Parakeet-TDT 0.6B v3, CC-BY-4.0)
    ];
  };
}
