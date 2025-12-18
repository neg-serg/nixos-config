{pkgs, ...}: {
  boot.kernel.sysctl = {
    "fs.file-max" = 524288;
    "kernel.sched_cfs_bandwidth_slice_us" = 3000; # better settings for cfs
    "net.ipv4.tcp_fin_timeout" = 5; # decrease default fin timeout
    "vm.max_map_count" = 16777216; # need for some games
    "vm.swappiness" = 10; # avoid swapping under load on 64GB RAM
  };

  services.udev.packages = [pkgs.dualsensectl];

  environment.systemPackages = [
    pkgs.dualsensectl # tool for controlling DualSense controllers
    # (inputs.nix-gaming.packages.${hostPlatform.system}.star-citizen.override {
    #   location = "$HOME/games/star-citizen";
    # })
  ];
}
