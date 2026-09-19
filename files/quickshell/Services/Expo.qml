pragma Singleton

import QtQuick
import Quickshell

// Workspace overview (hyprexpo) control, shared by the panel and Hyprland.
//
// Why `hyprctl eval` and not a dispatch: hyprexpo is dlopen'd by the generated
// hyprexpo-setup helper *after* hyprland.lua has been parsed, so in Lua-config
// mode the plugin registers no dispatcher that the config path accepts —
// `hyprctl dispatch hyprexpo:expo toggle` and `hl.dispatch(hyprexpo:expo toggle)`
// both die with "expected a dispatcher" (reproduced in a nested session; see
// docs/howto/hyprland-plugin.md). Evaluating the plugin's own Lua API is the
// supported route, and it is what the SUPER+grave bind in
// files/gui/hypr/hyprland.lua already uses.
//
// Keeping the command here means the workspace capsule click, the panel IPC
// entry point (`quickshell ipc call globalIPC toggleOverview`) and the compositor
// bind cannot drift apart.
Item {
    id: root

    readonly property var _toggleCommand: ["hyprctl", "eval", 'hl.plugin.hyprexpo.expo("toggle")']

    // Toggle the overview. A no-op when the plugin is absent (safe-mode sessions
    // start before hyprexpo-setup ran); hyprctl reports that on stdout, which
    // nobody reads here.
    function toggle(): void {
        Quickshell.execDetached(root._toggleCommand);
    }
}
