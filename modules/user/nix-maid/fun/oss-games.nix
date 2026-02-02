{
  pkgs,
  lib,
  neg,
  config,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.mangohud # Gaming HUD (was zen5 opt)
      ];
    }
    (lib.mkIf config.features.games.oss.enable {
      environment.systemPackages = [
        pkgs.abuse # classic side-scrolling shooter customizable with LISP
        pkgs.airshipper # Veloren voxel client/launcher
        pkgs.angband # roguelike
        pkgs.brogue-ce # roguelike (community edition)
        pkgs.crawl # roguelike
        pkgs.crawlTiles # roguelike tiles build
        pkgs.endless-sky # space exploration game
        pkgs.fheroes2 # free Heroes 2 implementation
        pkgs.flare # fantasy action RPG using the FLARE engine
        pkgs.gnuchess # GNU chess engine
        pkgs.gzdoom # open-source Doom engine
        pkgs.jazz2 # open source Jazz Jackrabbit 2
        pkgs.shattered-pixel-dungeon # roguelike
        pkgs.superTux # 2D platformer
        pkgs.superTuxKart # arcade kart racer
        pkgs.wesnoth # turn-based strategy with campaigns
        pkgs.xaos # interactive fractal explorer
        pkgs.xonotic # arena FPS
        pkgs.zeroad # RTS set in ancient warfare
      ];
    })

    (n.mkHomeFiles {
      # Mangohud Config
      ".config/MangoHud/MangoHud.conf".text = lib.generators.toKeyValue { } {
        cpu_stats = true;
        cpu_temp = true;
        gpu_stats = true;
        gpu_temp = true;
        vulkan_driver = true;
        fps = true;
        frametime = true;
        frame_timing = true;
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
    })
  ];
}
