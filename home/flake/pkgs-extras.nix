{pkgs, ...}: {
  hy3Plugin = pkgs.hyprlandPlugins.hy3;
  bpf-host-latency = pkgs.neg.bpf_host_latency;
}
