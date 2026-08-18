{
  pkgs,
  lib,
  config,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  # stable-diffusion.cpp (Vulkan) T2I on RX 9070 XT; binary renamed to sd-img
  # to avoid colliding with the Rust `sd` (sed replacement, golden-tools).
  sd-cpp = (pkgs.stable-diffusion-cpp.override { vulkanSupport = true; }).overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      if [ -e "$out/bin/sd" ] && [ ! -e "$out/bin/sd-img" ]; then
        mv "$out/bin/sd" "$out/bin/sd-img"
      fi
    '';
  });
in
{
  environment.systemPackages = lib.optionals enabled [
    # Most LLM CLI tools (aichat, aider-chat, codex) live in dev shells
    pkgs.voxinput # voice→text via LocalAI/OpenAI + dotool/uinput (system-level utility)
    sd-cpp # T2I via Vulkan (RADV); models in /zero/ai/image
  ];
}
