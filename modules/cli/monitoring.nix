{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.below # BPF-based system history
    pkgs.bpftrace # high-level eBPF tracer
    pkgs.goaccess # realtime log analyzer
    pkgs.kmon # kernel activity monitor
    pkgs.lnav # fancy log viewer
    pkgs.viddy # modern watch with history
    pkgs.zfxtop # Cloudflare/ZFX top-like monitor
  ];
}
