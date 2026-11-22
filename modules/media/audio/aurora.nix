##
# Module: media/audio/aurora
# Purpose: aurora — the local MPD player with its own Vulkan UI. One package,
# two binaries (aurora, aurora-probe); it talks to the MPD daemon that
# modules/servers/mpd already configures and serves MPRIS on the session bus.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.aurora";
  # mod4+f toggles the player the way the scratchpad keys do: the first press starts aurora, the
  # next one parks it out of sight, the one after that brings it back.
  #
  # The window class is `player`, not `aurora`: the crate sets that Wayland app_id itself
  # (~/src/aurora, with_name("player", "player")) and the Hyprland rules in
  # files/gui/hypr/hyprland.lua match `^(player)$`. Matching the binary name here focused
  # nothing, so every press fell through to starting another copy.
  #
  # Hyprland has no "hide this window" dispatcher, and the moves that would emulate one act on the
  # *focused* window only — the legacy `focuswindow`/`movetoworkspacesilent` string dispatchers are
  # not wired in 0.56 at all, so there is no reliable "move that window over there" from a script.
  # The player therefore lives on its own special workspace from the moment it maps (the
  # `workspace = "special:aurora silent"` window rule in files/gui/hypr/hyprland.lua parks it
  # there without yanking the view), and the key simply toggles that workspace: shown = the player
  # is up, hidden = parked. First press starts the player and reveals the workspace once its
  # window actually exists, so a failed launch never leaves an empty special workspace on screen.
  playerClass = "player";
  playerWorkspace = "aurora";
  # Where the external plugins live. `environment.sessionVariables` below is the session-wide
  # answer, and a session imports it when it *starts*: a compositor that outlives a `switch` keeps
  # exporting the previous generation's store path, so the player it starts finds the old bundle
  # and says `[plugins] unknown plugin musicbrainz`. This launcher is what starts the player, so it
  # pins the directory its own generation names — the next launch picks up a rebuilt plugin
  # package with no re-login and no compositor restart.
  pluginDir = "${pkgs.neg.aurora-plugins}/lib/aurora/plugins";
  # The live instrument's producer. The `spectroscope` plugin draws whatever
  # `$XDG_RUNTIME_DIR/aurora-scope` carries — a text pipe of decimal samples — and nothing else on
  # this machine writes it, which is why the plugin used to stand there dead. `pw-record` captures
  # the monitor of the sink MPD is pinned to (`game-stereo`, modules/servers/mpd), the script turns
  # f32 frames into that text. The rate is spelled twice on purpose: the samples are produced at
  # this rate, while the player's own fallback would be MPD's `audio:` line, which describes the
  # stream the daemon decodes rather than the monitor this captures.
  scopeRate = 48000;
  scopeFeed = pkgs.writeShellScript "aurora-scope-feed" ''
    set -eu
    fifo="''${XDG_RUNTIME_DIR:?}/aurora-scope"
    # The player opens the path but never creates it, so the pipe is ours to make: a fresh session
    # would otherwise have a producer with nowhere to write.
    [ -p "$fifo" ] || { rm -f "$fifo"; mkfifo -m 0600 "$fifo"; }
    exec ${lib.getExe' pkgs.pipewire "pw-record"} --target game-stereo \
      --rate ${toString scopeRate} --channels 1 --format f32 - \
      | exec ${lib.getExe pkgs.python3} ${config.lib.neg.path "files/media/aurora-scope-feed.py"} "$fifo"
  '';
  aurora-focus = pkgs.writeShellScriptBin "aurora-focus" ''
    set -eu
    # See `pluginDir`: the session's copy of this variable is older than the last switch.
    export AURORA_PLUGIN_DIR=${lib.escapeShellArg pluginDir}
    hyprctl=${pkgs.hyprland}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq
    up() { $hyprctl clients -j 2>/dev/null | $jq -e --arg c ${lib.escapeShellArg playerClass} 'any(.[]; .class == $c)' > /dev/null; }
    shown() { $hyprctl monitors -j 2>/dev/null | $jq -e --arg w "special:${playerWorkspace}" 'any(.[]; .specialWorkspace.name == $w)' > /dev/null; }

    if ! up; then
      # Start detached, so the launcher does not hold the window. `--scope-rate` names the rate
      # `scopeFeed` above writes at: the instrument's scale is only as good as this number, and the
      # daemon's own `audio:` line is not the one to trust for it.
      setsid ${pkgs.neg.aurora}/bin/aurora --scope-rate=${toString scopeRate} "$@" > /dev/null 2>&1 < /dev/null &
      # Wait for the window to map (the rule parks it on the workspace, it is not shown yet).
      i=0
      while [ "$i" -lt 150 ] && ! up; do
        sleep 0.2
        i=$((i + 1))
      done
      up || exit 1
    fi
    # The key owns both halves: the same press shows and hides the player.
    $hyprctl dispatch ${lib.escapeShellArg ''hl.dsp.workspace.toggle_special("${playerWorkspace}")''}
    # Hiding parks the player, and the press is finished: the pointer stays where the user left it.
    # Showing hands the screen to the player, so the pointer goes with the screen — to the middle of
    # the window, read out of the client list because nothing else lives on this workspace.
    # `cursor:warp_on_change_workspace` does not do this for a special workspace (measured on
    # 0.56.2: the toggle leaves the pointer where it was), so the move is explicit.
    shown || exit 0
    pos=$($hyprctl clients -j 2>/dev/null | $jq -r --arg c ${lib.escapeShellArg playerClass} \
      '[.[] | select(.class == $c)][0] | "\(.at[0] + ((.size[0] / 2) | floor)) \(.at[1] + ((.size[1] / 2) | floor))"')
    [ -n "$pos" ] || exit 0
    x=''${pos% *}
    y=''${pos#* }
    $hyprctl dispatch "hl.dsp.cursor.move({ x = $x, y = $y })"
  '';
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [
      pkgs.neg.aurora # aurora: MPD player with a Vulkan UI (winit + ash + cosmic-text)
      pkgs.neg.aurora-tools # headphones: the model catalogue CLI (apply/import/export)
      pkgs.neg.aurora-plugins # the eight external plugins: notify, scrobble, mpris, remaining, autodj, lyrics, musicbrainz, spectroscope
      aurora-focus # what mod4+f runs: focus the player, or start it if it is not up
    ];

    # The scope's producer, as a session service rather than a child of the player: the pipe is a
    # resource of the session, and a player that restarts has to find it already flowing. The
    # process blocks on the pipe's write end until the player opens the read end, so a session
    # with no player up costs no CPU; `audioGraph` is what orders it after PipeWire and WirePlumber.
    systemd.user.services.aurora-scope = config.lib.neg.systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "audioGraph"
        "restartAlways"
      ];
      description = "aurora: the playing audio as numbers on the scope FIFO";
      serviceConfig = {
        ExecStart = scopeFeed;
        # A PipeWire restart takes the capture stream away and `pw-record` exits; the preset wants
        # the unit back whatever the exit looked like, and this is the pause between attempts.
        RestartSec = 2;
      };
    };

    # The player asks the compositor for a translucent window: the swapchain uses a
    # premultiplied alpha mode and the frame's own ground carries the alpha, so what is behind
    # the window survives. Blurring that backdrop is the compositor's half, and it is what makes
    # the window read as glass instead of as a see-through hole.
    environment.sessionVariables.AURORA_WINDOW_OPACITY = "0.92";

    # The eight plugins that talk to the rest of the machine — notifications, scrobbling, MPRIS, the
    # queue's time left and its top-up, the lyrics line, the release lookup and the spectrogram —
    # are programs in a repository of their own, and the player finds them by looking in a plugin
    # directory: one directory per plugin, its `plugin.json` and the program beside it. The package
    # installs all eight under `$out/lib/aurora/plugins`, and this variable is the session-wide
    # answer of the contract — a rebuilt plugin is picked up by the next player start, with no
    # rebuild of the player. The launcher above names the same directory from its own generation,
    # for the session that outlived a switch. An explicitly empty value means "no external
    # plugins", which is what a capture that must not depend on the machine says.
    environment.sessionVariables.AURORA_PLUGIN_DIR = pluginDir;
  };
}
