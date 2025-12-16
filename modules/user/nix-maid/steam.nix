{pkgs, ...}: {
  home.packages = [
    (pkgs.writeScriptBin "game-session" ''
      #!/usr/bin/env bash
      set -xeuo pipefail

      gamescopeArgs=(
        # --adaptive-sync # VRR support
        --hdr-enabled
        # --mangoapp # performance overlay
        --rt
        --steam
        --hdr-debug-force-output
      )

      steamArgs=(
        -pipewire-dmabuf
        -tenfoot
      )

      export DXVK_HDR=1
      exec gamescope "''${gamescopeArgs[@]}" -- steam "''${steamArgs[@]}"
    '')
    (pkgs.writeScriptBin "game-session-mangohud" ''
      #!/usr/bin/env bash
      set -xeuo pipefail

      gamescopeArgs=(
        --adaptive-sync # VRR support
        --hdr-enabled
        --mangoapp # performance overlay
        --rt
        --steam
      )
      steamArgs=(
        -pipewire-dmabuf
        -tenfoot
      )
      mangoConfig=(
        cpu_temp
        gpu_temp
        ram
        vram
      )
      mangoVars=(
        MANGOHUD=1
        MANGOHUD_CONFIG="$(
          IFS=,
          echo "''${mangoConfig[*]}"
        )"
      )

      export "''${mangoVars[@]}"
      exec gamescope "''${gamescopeArgs[@]}" -- steam "''${steamArgs[@]}"
    '')
    pkgs.bottles # Wine prefix manager for gaming
    pkgs.dualsensectl # DualSense controller configuration
  ];
}