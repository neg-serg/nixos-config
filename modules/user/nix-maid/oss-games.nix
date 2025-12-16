{
  pkgs,
  lib,
  ...
}: {
  environment.systemPackages = with pkgs; [
    mangohud # Gaming HUD
    superTux # 2D platformer
    superTuxKart # arcade kart racer
    wesnoth # turn-based strategy with campaigns
    xonotic # arena FPS
    zeroad # RTS set in ancient warfare
  ];

  # Mangohud Config
  users.users.neg.maid.file.home.".config/MangoHud/MangoHud.conf".text = lib.generators.toKeyValue {} {
    cpu_stats = true;
    cpu_temp = true;
    gpu_stats = true;
    gpu_temp = true;
    vulkan_driver = true;
    fps = true;
    frametime = true;
    frame_timing = true;
    # enableSessionWide = true; # Not supported in config file direct mapping usually, environment var handles it
    font_size = 10;
    position = "top-left";
    engine_version = true;
    wine = true;
    no_display = true;
    toggle_hud = "Shift_R+F12";
    toggle_fps_limit = "Shift_R+F1";
    background_color = "020202";
    battery_color = "6c7e96";
    cpu_color = "0a3749";
    cpu_load_color = "005200, 005faf, 8a2f58";
    engine_color = "5b5bbb";
    fps_color = "005200, 005faf, 8a2f58";
    frametime_color = "005200";
    gpu_color = "005200";
    gpu_load_color = "005200, 005faf, 8a2f58";
    io_color = "005faf";
    media_player_color = "8d9eb2";
    text_color = "8d9eb2";
    text_outline_color = "020202";
    vram_color = "005f87";
    wine_color = "5b5bbb";
  };
}
