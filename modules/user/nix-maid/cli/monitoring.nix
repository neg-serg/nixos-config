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
  # --- Btop Config Generator ---
  mkBtopConf =
    attrs:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        k: v:
        let
          val =
            if builtins.isBool v then
              (if v then "true" else "false")
            else if builtins.isInt v then
              builtins.toString v
            else
              ''"${builtins.toString v}"'';
        in
        "${k} = ${val}"
      ) attrs
    );

  btopSettings = {
    color_theme = "midnight-ocean";
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
    update_ms = 100;
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
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.btop # A monitor of resources (CPU, Memory, Network)
        pkgs.hwatch # Modern alternative to watch command with history
        pkgs.s-tui # Stress terminal UI for CPU monitoring
        pkgs.sysdig # System-wide visibility tool
        pkgs.glances # Cross-platform system monitoring tool
      ]
      ++ (lib.optionals
        (config.profiles.network.wifi.enable || (config.features.net.wifi.enable or false))
        [
          pkgs.wavemon # Wireless device monitoring
        ]
      );
    }
    (n.mkHomeFiles {
      # Btop Config
      ".config/btop/btop.conf".text = mkBtopConf btopSettings;
      ".config/btop/themes/midnight-ocean.theme".source =
        ../../../../files/shell/btop/themes/midnight-ocean.theme;

      # Glances Config (Optimized)
      ".config/glances/glances.conf".text = ''
        [global]
        refresh=5
        check_update=false
        history_size=0
      '';
    })
  ];
}
