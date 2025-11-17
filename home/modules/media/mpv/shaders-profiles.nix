{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  xdg = import ../../lib/xdg-helpers.nix { inherit lib pkgs; };
  shadersDir = "mpv/shaders";
  note = ''
FSRCNNX / SSimSuperRes / Anime4K shaders

Place shader GLSL files into this directory to enable the profiles:

- FSRCNNX x2:         FSRCNNX_x2_8-0-4-1.glsl
- SSimSuperRes:       SSimSuperRes.glsl
- KrigBilateral:      KrigBilateral.glsl (optional chroma upsampler variant)
- Anime4K (x2 base):  Anime4K_Upscale_CNN_x2_S.glsl

Recommended toggles (configured in mpv):
- Alt+1 → FSRCNNX x2 (+SSimSR finisher)
- Alt+2 → Anime4K x2 (S preset)
- Alt+0 → Disable GLSL shaders (return to defaults)

Files are not bundled to keep the repo lean. You can copy them from the upstream projects
or from an existing shader pack. Profiles will safely do nothing if files are absent.
'';
in
mkIf (config.features.gui.enable or false) (
  mkMerge [
    (xdg.mkXdgText "${shadersDir}/README.txt" note)
    {
      # Profiles apply GLSL shaders when present. If missing, mpv logs an error and continues.
      programs.mpv.profiles = {
        "ai-off" = {
          glsl-shaders = [ ];
        };
        "ai-fsrcnnx" = {
          # Apply FSRCNNX first, then SSimSR as a finisher when present.
          glsl-shaders = [
            "~~/shaders/FSRCNNX_x2_8-0-4-1.glsl"
            "~~/shaders/SSimSuperRes.glsl"
          ];
          # Prefer good chroma upscaling alongside
          cscale = "ewa_lanczos";
        };
        "ai-anime4k" = {
          glsl-shaders = [
            "~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"
          ];
          cscale = "ewa_lanczos";
        };
      };

      # Keybindings to quickly switch shader profiles at runtime
      programs.mpv.bindings = {
        "Alt+0" = "apply-profile ai-off";
        "Alt+1" = "apply-profile ai-fsrcnnx";
        "Alt+2" = "apply-profile ai-anime4k";
      };
    }
  ])
