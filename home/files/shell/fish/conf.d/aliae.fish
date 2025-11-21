#!/usr/bin/env fish
# Aliae integration for fish
if type -q aliae
    set -l cfg (test -n "$XDG_CONFIG_HOME"; and echo "$XDG_CONFIG_HOME/aliae/config.yaml"; or echo "$HOME/.config/aliae/config.yaml")
    aliae init fish --config $cfg --print | source
end
