{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  inherit (config.users.users.neg) home;
in
lib.mkMerge [
  {
    environment.systemPackages = [
      pkgs.aliae # Shell alias manager
      pkgs.fastfetch # System info tool (neofetch successor)
      pkgs.tealdeer # Fast tldr client
      pkgs.nxv # Find any version of any Nix package instantly
    ];

    environment.variables = {
      HTTPIE_CONFIG_DIR = "${home}/.config/httpie";
      PARALLEL_HOME = "${home}/.config/parallel";
    };
  }

  (neg.mkHomeFiles {
    ".config/fastfetch/config.jsonc".text = ''
      {
        "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
        "logo": {
          "source": "$XDG_CONFIG_HOME/fastfetch/skull",
          "padding": {
            "left": 4,
            "right": 4
          },
          "color": {
            "1": "#395573",
            "2": "#477AB3",
            "3": "#6096BF",
            "4": "#53A6A6"
          }
        },
        "display": {
          "brightColor": true,
          "separator": "  ",
          "size": {
            "maxPrefix": "TB"
          },
          "percent": {
            "type": 3
          },
          "color": {
            "output": "#9FB4CC",
            "keys": "1;#477AB3",
            "separator": "#395573"
          },
          "bar": {
            "char": {
              "elapsed": "━",
              "total": "─"
            },
            "width": 22,
            "border": {
              "left": " ",
              "right": " "
            },
            "color": {
              "elapsed": "#53A6A6",
              "total": "#27303C"
            }
          }
        },
        "modules": [
          { "type": "title", "format": "{1}@{2}", "color": { "user": "#53A6A6", "at": "#395573", "host": "1;#BF85CC" } },
          { "type": "separator", "string": "─", "times": 45 },
          { "type": "os", "key": "", "format": "{3}" },
          { "type": "kernel", "key": "", "format": "{1} {2} ({4})" },
          { "type": "uptime", "key": "" },
          { "type": "command", "key": "", "text": "n=$(timeout -k 1 3 nix-store --query --requisites /run/current-system 2>/dev/null | wc -l); [ $n -gt 0 ] 2>/dev/null && echo $n '(nix; /run/current-system)' || echo nix-store-busy" },
          { "type": "host", "key": "" },
          { "type": "monitor", "key": "" },
          { "type": "theme", "key": "" },
          { "type": "icons", "key": "" },
          { "type": "cursor", "key": "" },
          { "type": "shell", "key": "" },
          { "type": "wm", "key": "" },
          { "type": "terminal", "key": "" },
          { "type": "terminalfont", "key": "" },
          { "type": "terminalsize", "key": "" },
          { "type": "cpu", "key": "", "temp": true },
          { "type": "gpu", "key": "󰢮", "driverSpecific": true, "temp": true, "percent": { "type": 1 } },
          { "type": "memory", "key": "" },
          { "type": "board", "key": "" },
          { "type": "bios", "key": "" },
          { "type": "swap", "key": "󰄢" },
          { "type": "disk", "key": "", "folders": ["/"] },
          { "type": "disk", "key": "󰙃", "folders": ["/zero"] },
          { "type": "localip", "key": "", "defaultRouteOnly": true },
          { "type": "vulkan", "key": "󰢮" },
          { "type": "sound", "key": "" },
          { "type": "player", "key": "" },
          { "type": "users", "key": "" },
          { "type": "locale", "key": "" },
          { "type": "command", "key": "", "text": "curl -s --max-time 4 'https://wttr.in/?format=%C+%t' 2>/dev/null || true" },
          { "type": "break" },
          { "type": "colors", "symbol": "circle", "paddingLeft": 0 }
        ]
      }
    '';

    ".config/fastfetch/skull".text = builtins.readFile (config.lib.neg.path "files/fastfetch/skull");

    ".config/amfora".source = config.lib.neg.path "files/config/amfora";

    ".config/tealdeer/config.toml".text = ''
      [style.description]
      underline = false
      bold = false
      italic = true

      [style.command_name]
      foreground = "cyan"
      underline = false
      bold = false
      italic = false

      [style.example_text]
      foreground = "green"
      underline = false
      bold = false
      italic = false

      [style.example_code]
      foreground = "yellow"
      underline = false
      bold = false
      italic = true

      [style.example_variable]
      foreground = "blue"
      underline = false
      bold = true
      italic = false

      [display]
      compact = false
      use_pager = false

      [updates]
      auto_update = true
      auto_update_interval_hours = 720

      [directories]
    '';
  })
]
