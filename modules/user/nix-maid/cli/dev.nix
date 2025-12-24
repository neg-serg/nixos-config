{pkgs, ...}: {
  config = {
    environment.systemPackages = [
      pkgs.direnv # Extension for your shell to load/unload env vars
      pkgs.nix-direnv # A fast, persistent use_nix implementation for direnv
      pkgs.nh # Yet another nix helper (CLI for NixOS/Home Manager)
      pkgs.process-compose # Process orchestrator (docker-compose but for processes)
      pkgs.kubecolor # Colorize kubectl output
      pkgs.nix-search-tv # TUI for searching libraries on search.nixos.org
    ];
  };
}
