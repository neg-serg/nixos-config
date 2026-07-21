{
  config,
  inputs,
  lib,
  ...
}: {
  # Route Hyprland and its portal to the flake-pinned versions
  # Gated behind features.gui.enable to avoid pkgs.hyprland evaluation on headless hosts
  config = lib.mkIf config.features.gui.enable {
    nixpkgs.overlays = [
      inputs.hyprland.overlays.hyprland-packages
      inputs.xdg-desktop-portal-hyprland.overlays.default
      (final: prev: {
        hyprglass = final.stdenv.mkDerivation {
          pname = "hyprglass";
          version = "0.7.0";
          src = final.fetchFromGitHub {
            owner = "hyprnux";
            repo = "hyprglass";
            rev = "v0.7.0";
            hash = "sha256-x/584kY+XXlU/OWKtZAFo89VtowjLXs1DiP9PC0o0Os=";
          };

          nativeBuildInputs = with final; [ pkg-config ];
          buildInputs = with final; [
            hyprland hyprland.dev aquamarine hyprutils hyprgraphics hyprcursor hyprlang
            hyprland-protocols wayland wayland-protocols pixman libdrm libinput
            libGL libglvnd cairo libxkbcommon libxcb libxcb-util libxcb-wm
            libxcb-image libxcb-render-util libxcb-errors glslang lua
          ];
          env.PKG_CONFIG_PATH = "${final.hyprland.dev}/share/pkgconfig";

          postPatch = ''
            sed -i 's/layerSurface->alpha()\.getTotal()/layerSurface->m_alpha->value()/' src/main.cpp
            sed -i 's/Desktop::viewState()->windows()/g_pCompositor->m_windows/' src/main.cpp
            sed -i 's/window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT)/window->m_realPosition->value()/' src/GlassDecoration.cpp
            sed -i 's/window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT)/window->m_realSize->value()/' src/GlassDecoration.cpp
            sed -i 's/layerSurface->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT)/layerSurface->m_realPosition->value()/' src/LayerGeometry.hpp
            sed -i 's/layerSurface->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT)/layerSurface->m_realSize->value()/' src/LayerGeometry.hpp
            sed -i 's/layerSurface->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT)/layerSurface->m_realPosition->value()/' src/GlassLayerSurface.cpp
            sed -i 's/layerSurface->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT)/layerSurface->m_realSize->value()/' src/GlassLayerSurface.cpp
            sed -i 's/layerSurface->positionAnimation()->isBeingAnimated()/layerSurface->m_realPosition->isBeingAnimated()/g' src/GlassLayerSurface.cpp
            sed -i 's/layerSurface->sizeAnimation()->isBeingAnimated()/layerSurface->m_realSize->isBeingAnimated()/g' src/GlassLayerSurface.cpp
            sed -i 's/layerSurface->alpha()\[Desktop::View::LS_ALPHA_FADE\]->isBeingAnimated()/layerSurface->m_alpha->isBeingAnimated()/g' src/GlassLayerSurface.cpp
          '';

          installPhase = ''
            mkdir -p $out/lib
            cp hyprglass.so $out/lib/
          '';
        };

        hyprlandPlugins = prev.hyprlandPlugins // {
          inherit (final) hyprglass;
        };
      })
    ];
  };
}
