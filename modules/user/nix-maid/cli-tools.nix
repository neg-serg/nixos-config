{
  pkgs,
  lib,
  config,
  impurity,
  ...
}: let
  # Source paths (must be Nix paths for impurity.link)
  fastfetchSrc = ../../../files/fastfetch;
  # --- Bat Config (syntaxes disabled due to HM batCache conflict) ---
  # batSyntaxes = {
  #   ".config/bat/syntaxes/Dockerfile_with_bash.sublime-syntax".text = ''
  #     %YAML 1.2
  #     ---
  #     name: Dockerfile (with bash)
  #     scope: source.dockerfile.bash
  #     contexts:
  #       main:
  #         - include: scope:source.dockerfile
  #   '';
  #   ".config/bat/syntaxes/JSON.sublime-syntax".text = ''
  #     %YAML 1.2
  #     ---
  #     name: JSON
  #     scope: source.json
  #     contexts:
  #       main:
  #         - include: arrays
  #       arrays:
  #         - match: '\G\['
  #           push: arrays
  #         - match: ']'
  #           pop: true
  #         - match: '.'
  #           scope: constant.character
  #   '';
  # };
  # --- Btop Config Generator ---
  mkBtopConf = attrs:
    lib.concatStringsSep "\n" (lib.mapAttrsToList (
        k: v: let
          val =
            if builtins.isBool v
            then
              (
                if v
                then "true"
                else "false"
              )
            else if builtins.isInt v
            then builtins.toString v
            else ''"${builtins.toString v}"'';
        in "${k} = ${val}"
      )
      attrs);

  btopSettings = {
    color_theme = "neg";
    theme_background = true;
    truecolor = true;
    force_tty = false;
    presets = "cpu:1:default,proc:0:default cpu:0:default,mem:0:default,net:0:default cpu:0:block,net:0:tty";
    vim_keys = true;
    rounded_corners = false;
    graph_symbol = "braille";
    graph_symbol_cpu = "default";
    graph_symbol_gpu = "default";
    graph_symbol_mem = "default";
    graph_symbol_net = "default";
    graph_symbol_proc = "default";
    shown_boxes = "cpu proc";
    update_ms = 2000;
    proc_sorting = "cpu direct";
    proc_reversed = false;
    proc_tree = false;
    proc_colors = true;
    proc_gradient = true;
    proc_per_core = true;
    proc_mem_bytes = true;
    proc_cpu_graphs = true;
    proc_info_smaps = false;
    proc_left = true;
    proc_filter_kernel = true;
    proc_aggregate = true;
    cpu_graph_upper = "total";
    cpu_graph_lower = "total";
    show_gpu_info = "Auto";
    cpu_invert_lower = true;
    cpu_single_graph = false;
    cpu_bottom = false;
    show_uptime = true;
    check_temp = true;
    cpu_sensor = "Auto";
    show_coretemp = true;
    cpu_core_map = "";
    temp_scale = "celsius";
    base_10_sizes = false;
    show_cpu_freq = true;
    clock_format = "%X";
    background_update = true;
    custom_cpu_name = "";
    disks_filter = "";
    mem_graphs = false;
    mem_below_net = false;
    zfs_arc_cached = true;
    show_swap = true;
    swap_disk = true;
    show_disks = false;
    only_physical = true;
    use_fstab = true;
    zfs_hide_datasets = false;
    disk_free_priv = false;
    show_io_stat = true;
    io_mode = true;
    io_graph_combined = false;
    io_graph_speeds = "";
    net_download = 100;
    net_upload = 100;
    net_auto = true;
    net_sync = false;
    net_iface = "";
    show_battery = false;
    selected_battery = "Auto";
    log_level = "WARNING";
    nvml_measure_pcie_speeds = true;
    gpu_mirror_graph = true;
  };

  # --- Yazi Configs ---
  yaziFormat = pkgs.formats.toml {};

  yaziSettings = {
    mgr = {show_hidden = true;};
    opener.edit = [
      {
        run = ''nvim "$@"'';
        block = true;
      }
    ];
  };

  yaziTheme = {
    manager = {
      cwd = {fg = "#367bbf";};
      hovered = {
        fg = "#367bbf";
        bg = "#0d1824";
      };
      preview_hovered = {underline = true;};
      find_keyword = {
        fg = "#FFFF7D";
        italic = true;
      };
      find_position = {
        fg = "#367bbf";
        bg = "reset";
        italic = true;
      };
      marker_copied = {
        fg = "#7DFF7E";
        bg = "#7DFF7E";
      };
      marker_cut = {
        fg = "#CF4F88";
        bg = "#CF4F88";
      };
      marker_selected = {
        fg = "#367bbf";
        bg = "#367bbf";
      };
      tab_active = {
        fg = "#000000";
        bg = "#367bbf";
      };
      tab_inactive = {
        fg = "#6C7E96";
        bg = "#0d1824";
      };
      border_style = {fg = "#3D3D3D";};
      border_symbol = "│";
    };
    status = {
      separator_open = "";
      separator_close = "";
      separator_style = {
        fg = "#0d1824";
        bg = "#0d1824";
      };
      mode_normal = {
        fg = "#000000";
        bg = "#367bbf";
        bold = true;
      };
      mode_select = {
        fg = "#000000";
        bg = "#98d3cb";
        bold = true;
      };
      mode_unset = {
        fg = "#000000";
        bg = "#f274bc";
        bold = true;
      };
      progress_label = {
        fg = "#ffffff";
        bold = true;
      };
      progress_normal = {
        fg = "#367bbf";
        bg = "#0d1824";
      };
      progress_error = {
        fg = "#CF4F88";
        bg = "#0d1824";
      };
      permissions_t = {fg = "#367bbf";};
      permissions_r = {fg = "#FFFF7D";};
      permissions_w = {fg = "#CF4F88";};
      permissions_x = {fg = "#7DFF7E";};
      permissions_s = {fg = "#98d3cb";};
    };
    input = {
      border = {fg = "#367bbf";};
      title = {};
      value = {fg = "#6C7E96";};
      selected = {bg = "#0d1824";};
    };
    select = {
      border = {fg = "#98d3cb";};
      active = {fg = "#98d3cb";};
      inactive = {fg = "#6C7E96";};
    };
    tasks = {
      border = {fg = "#367bbf";};
      title = {};
      hovered = {
        fg = "#367bbf";
        underline = true;
      };
    };
    which = {
      cols = 3;
      mask = {bg = "#0d1824";};
      cand = {fg = "#98d3cb";};
      rest = {fg = "#6C7E96";};
      desc = {fg = "#367bbf";};
      separator = "  ";
      separator_style = {fg = "#3D3D3D";};
    };
    notify = {
      title_info = {fg = "#367bbf";};
      title_warn = {fg = "#FFC44E";};
      title_error = {fg = "#CF4F88";};
      icon_info = "ZE ";
      icon_warn = "ZE ";
      icon_error = "ZE ";
    };
    help = {
      on = {fg = "#367bbf";};
      exec = {fg = "#98d3cb";};
      desc = {fg = "#6C7E96";};
      hovered = {
        bg = "#0d1824";
        bold = true;
      };
      footer = {
        fg = "#6C7E96";
        bg = "#0d1824";
      };
    };
  };

  yaziKeymap = {
    mgr.prepend_keymap = [
      {
        run = "close";
        on = ["<Esc>"];
      }
      {
        run = "close";
        on = ["<C-q>"];
      }
      {
        run = "yank --cut";
        on = ["d"];
      }
      {
        run = "remove --force";
        on = ["D"];
      }
      {
        run = "remove --permanently";
        on = ["X"];
      }
      {
        on = ["f"];
        run = ''shell "$SHELL" --block'';
        desc = "Open $SHELL here";
      }
    ];
  };
in {
  # --- System Packages (ensure installed) ---
  environment.systemPackages = with pkgs; [
    bat # A cat(1) clone with wings (syntax highlighting)
    btop # A monitor of resources (CPU, Memory, Network)
    fzf # A command-line fuzzy finder
    yazi # Blazing fast terminal file manager (Rust/Async I/O)
    fastfetch # Like neofetch, but much faster (C)

    # Core Tools
    fd # A simple, fast and user-friendly alternative to 'find'
    ripgrep # Line-oriented search tool (grep alternative)
    direnv # Extension for your shell to load/unload env vars
    nix-direnv # A fast, persistent use_nix implementation for direnv

    # CLI Tools
    aliae # Cross-shell configuration manager
    superfile # Pretty fancy TUI file manager
    pkgs.nh # Yet another nix helper (CLI for NixOS/Home Manager)
    process-compose # Process orchestrator (docker-compose but for processes)

    # CLI Tools
    fabric-ai # Open-source framework for augmenting humans (AI framework)
    hwatch # Modern alternative to watch command with history
    kubecolor # Colorize kubectl output
    nix-search-tv # TUI for searching libraries on search.nixos.org
    numbat # High precision scientific calculator with unit support
    uni # Query the Unicode database from the command line
    tray-tui # System tray for TUI applications in terminal
    visidata # Terminal spreadsheet multitool for data discovery
    # ZCLI (custom script)
    (import ../../../files/scripts/zcli.nix {
      inherit pkgs;
      profile = "telfir"; # Host profile for script configuration
      repoRoot = "/etc/nixos";
      flakePath = "/etc/nixos/flake.nix";
      backupFiles = [];
    })
  ];

  # --- Nix-Maid Dotfiles ---
  users.users.neg.maid.file.home = {
    # Bat Config (syntaxes disabled due to HM batCache conflict)
    ".config/bat/config".text = ''
      --theme="ansi"
      --italic-text="always"
      --paging="never"
      --decorations="never"
    '';

    # Btop Config
    ".config/btop/btop.conf".text = mkBtopConf btopSettings;
    ".config/btop/themes/neg.theme".source = ../../../files/shell/btop/themes/neg.theme;

    # Yazi Configs
    ".config/yazi/yazi.toml".source = yaziFormat.generate "yazi.toml" yaziSettings;
    ".config/yazi/theme.toml".source = yaziFormat.generate "theme.toml" yaziTheme;
    ".config/yazi/keymap.toml".source = yaziFormat.generate "keymap.toml" yaziKeymap;

    # Fastfetch Configs (Source from repo)
    ".config/fastfetch/config.jsonc".source = impurity.link (fastfetchSrc + /config.jsonc);
    ".config/fastfetch/skull".source = impurity.link (fastfetchSrc + /skull); # Custom logo

    # FD Ignore
    ".config/fd/ignore".text = ''
      .git/
    '';

    # Ripgrep Config
    ".config/ripgrep/ripgreprc".text = ''
      --no-heading
      --smart-case
      --follow
      --hidden
      --glob=!.git/
      --glob=!node_modules/
      --glob=!yarn.lock
      --glob=!package-lock.json
      --glob=!.yarn/
      --glob=!_build/
      --glob=!tags
      --glob=!.pub-cache
    '';

    # Dircolors
    ".dircolors".source = ../../../files/shell/dircolors/dircolors;

    # --- Configs ---

    # Amfora Config
    ".config/amfora".source = ../../../files/config/amfora;

    # Dosbox Config
    ".config/dosbox".source = ../../../files/config/dosbox;

    # Icedtea Web Config
    ".config/icedtea-web".source = ../../../files/config/icedtea-web;

    # Wallust Config
    ".config/wallust/wallust.toml".source = ../../../files/wallust/wallust.toml;
    ".config/wallust/templates/hyprland.conf".source = ../../../files/wallust/templates/hyprland.conf;
    ".config/wallust/templates/kitty.conf".source = ../../../files/wallust/templates/kitty.conf;
    ".config/wallust/templates/dunstrc".source = ../../../files/wallust/templates/dunstrc;

    # Aliae Config (if needed later, currently empty in source)
  };

  # --- Environment Variables ---
  environment.variables = {
    RIPGREP_CONFIG_PATH = "${config.users.users.neg.home}/.config/ripgrep/ripgreprc";

    FZF_DEFAULT_COMMAND = "${lib.getExe pkgs.fd} --type=f --hidden --exclude=.git";
    FZF_DEFAULT_OPTS = builtins.concatStringsSep " " (builtins.filter (x: builtins.typeOf x == "string") [
      "--bind='alt-p:toggle-preview,alt-a:select-all,alt-s:toggle-sort'"
      "--bind='alt-d:change-prompt(Directories ❯ )+reload(fd . -t d)'"
      "--bind='alt-f:change-prompt(Files ❯ )+reload(fd . -t f)'"
      "--bind='ctrl-j:execute(v {+})+abort'"
      "--bind='ctrl-space:select-all'"
      "--bind='ctrl-t:accept'"
      "--bind='ctrl-v:execute(v {+})'"
      "--bind='ctrl-y:execute-silent(echo {+} | wl-copy)'"
      "--bind='tab:execute(handlr open {+})+abort'"
      "--ansi"
      "--layout=reverse"
      "--cycle"
      "--border=sharp"
      "--margin=0"
      "--padding=0"
      "--footer='[Alt-f] Files  [Alt-d] Dirs  [Alt-p] Preview  [Alt-s] Sort  [Tab] Open'"
      "--color=header:white"
      "--color=footer:underline"
      "--color=footer:white"
      "--exact"
      "--height=16"
      "--min-height=14"
      "--info=default"
      "--multi"
      "--no-mouse"
      "--no-scrollbar"
      "--prompt='❯  '"
      "--pointer=▶"
      "--marker=✓"
      "--with-nth=1.."
      # Colors
      "--color=preview-bg:-1"
      "--color=gutter:#000000"
      "--color=bg:#000000"
      "--color=bg+:#000000"
      "--color=fg:#4f5d78"
      "--color=fg+:#8DA6B2"
      "--color=hl:#546c8a"
      "--color=hl+:#005faf"
      "--color=border:#0b2536"
      "--color=list-border:#0b2536"
      "--color=input-border:#0b2536"
      "--color=preview-border:#000000"
      "--color=header-border:#0b2536"
      "--color=footer-border:#0b2536"
      "--color=separator:#0b2536"
      "--color=scrollbar:#0b2536"
      "--color=info:#3f5876"
      "--color=pointer:#005faf"
      "--color=marker:#04141C"
      "--color=prompt:#005faf"
      "--color=spinner:#3f5876"
      "--color=preview-fg:#4f5d78"
    ]);

    FZF_CTRL_R_OPTS = builtins.concatStringsSep " " [
      "--sort"
      "--exact"
      "--border=sharp --margin=0 --padding=0 --no-scrollbar"
      "--footer='[Enter] Paste  [Ctrl-y] Yank  [?] Preview'"
      "--preview 'echo {}'"
      "--preview-window down:5:hidden,wrap --bind '?:toggle-preview'"
    ];

    FZF_CTRL_T_OPTS = builtins.concatStringsSep " " [
      ''--border=sharp --margin=0 --padding=0 --no-scrollbar --preview 'if [ -d "{}" ]; then (eza --tree --icons=auto -L 2 --color=always "{}" 2>/dev/null || tree -C -L 2 "{}" 2>/dev/null); else (bat --style=plain --color=always --line-range :200 "{}" 2>/dev/null || highlight -O ansi -l "{}" 2>/dev/null || head -200 "{}" 2>/dev/null || file -b "{}" 2>/dev/null); fi' --preview-window=right,60%,border-left,wrap''
    ];
  };
}
