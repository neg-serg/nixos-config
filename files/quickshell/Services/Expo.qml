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
//
// The command is the `hypr-expo` helper (modules/user/nix-maid/hyprland/main.nix)
// rather than a bare `hyprctl eval`: the plugin is loaded exactly once, from the
// session-start hook, and a session that parsed its config in an older generation
// (the helper's store path is baked into the deployed hyprland.lua) can come up
// without hyprexpo at all. `hyprctl eval` answers "ok" in that case — the
// namespace is simply nil — so the click looked wired while the overview never
// appeared. The helper loads and configures the plugin on demand, then toggles.
Item {
    id: root

    readonly property var _toggleCommand: ["hypr-expo", "toggle"]

    // Toggle the overview; loads the plugin first when the session lost it.
    // A missing compositor socket or a missing plugin leaves hyprctl reporting
    // on stdout, which nobody reads here.
    function toggle(): void {
        Quickshell.execDetached(root._toggleCommand);
    }
}
