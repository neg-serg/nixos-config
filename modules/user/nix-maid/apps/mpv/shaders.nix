{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;

  # --- Shaders Sources ---
  fsrcnnx = pkgs.fetchurl {
    url = "https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_8-0-4-1.glsl";
    sha256 = "1bn2ilzg007nxrbg4y81i3rgagsk4ivmjv11hb68alf9q72xn078";
  };
  krig = pkgs.fetchurl {
    url = "https://gist.githubusercontent.com/igv/a015fc885d5c22e6891820ad89555637/raw/KrigBilateral.glsl";
    sha256 = "1c0cjjysi9gmqy7nwj5ywc39hk6ivxfrhw8drrpn90vvnymrhiwa";
  };
  anime4k = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/bloc97/Anime4K/master/glsl/Upscale/Anime4K_Upscale_CNN_x2_S.glsl";
    sha256 = "19294sb65z6ssyvnhr2pcgb2c5j2f00nn9nbggpgf23r50pfqlsc";
  };
  ssim = pkgs.fetchurl {
    url = "https://gist.githubusercontent.com/igv/2364ffa6e81540f29cb7ab4c9bc05b6b/raw/SSimSuperRes.glsl";
    sha256 = "03s62mwcj90pnpp7dmwa4lbh404805g3f6s1a1908q0chhap3cm8";
  };
in
{
  config = lib.mkIf (config.features.gui.enable or false) (
    n.mkHomeFiles {
      ".config/mpv/shaders/FSRCNNX_x2_8-0-4-1.glsl".source = fsrcnnx;
      ".config/mpv/shaders/KrigBilateral.glsl".source = krig;
      ".config/mpv/shaders/Anime4K_Upscale_CNN_x2_S.glsl".source = anime4k;
      ".config/mpv/shaders/SSimSuperRes.glsl".source = ssim;
    }
  );
}
