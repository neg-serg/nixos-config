pragma Singleton
import QtQuick
import Quickshell
import qs.Components

// tray-raise: the "Open Telegram" entry in a tray menu, made to work.
//
// A Qt app cannot raise its own window on Wayland — Qt's Wayland client
// implements no xdg-activation, so `QWindow::requestActivate()`, which is what
// Telegram's tray entry does, never reaches the compositor. The entry therefore
// fires and nothing moves: no error, no window. The window-activate helper does
// what the app cannot: it focuses the window through Hyprland (special
// workspaces included), and it owns the whole policy — which labels mean "bring
// it up" (--open-prefix) and the tray-id → window-class exceptions
// (~/.config/menu-search/window-class.tsv). This singleton only tells it what
// was clicked, so the tray menu, menu-search and the keybind all end up raising
// windows the same way.
//
// `trayContext` must be set whenever a tray context menu is opened (SystemTray
// does): the menu entries of a StatusNotifierItem do not carry the item's id,
// and that id is what identifies the window. An empty context is silently a
// no-op, which is what a menu that is not a tray menu (Hiddify in
// NetClusterCapsule) gets.
QtObject {
    id: root

    // Identity of the tray app whose context menu is currently open. Shape of
    // SystemTrayItem: `id` ("TelegramDesktop"), `title` ("Telegram").
    property var trayContext: null

    function setContext(item) {
        if (!item) { trayContext = null; return; }
        const id = String(item.id || "");
        trayContext = id ? { id: id, title: String(item.title || "") } : null;
    }

    function clearContext() { trayContext = null; }

    // Mirror of DelegateEntry.entryLabel: `text`, then `label`, then `title`.
    function labelOf(entry) {
        if (!entry) return "";
        if (entry.text && String(entry.text).length) return String(entry.text);
        if (entry.label && String(entry.label).length) return String(entry.label);
        if (entry.title && String(entry.title).length) return String(entry.title);
        return "";
    }

    // Call right after triggering a tray menu entry: if the entry promised to
    // bring the app up, make that true. Returns true when a helper was started.
    function raiseForEntry(entry) {
        if (!trayContext) return false;
        const label = labelOf(entry);
        if (!label) return false;
        const id = trayContext.id;
        _output = "";
        // --stdout-report: the runner below consumes stdout only, and what the
        // helper did belongs in the session log next to the click.
        _cmd = ["window-activate", "--raise-for", id, "--tray-title", trayContext.title, "--stdout-report"];
        _timeout.restart();
        _raise.start();
        return true;
    }

    property var _cmd: []
    property string _output: ""

    // QtObject has no default property, so children are declared as properties.
    property ProcessRunner _raise: ProcessRunner {
        id: _raise
        autoStart: false
        // A one-shot per click: the default would re-run the same command forever.
        restartMode: "never"
        restartOnExit: false
        cmd: root._cmd
        // Only what window-activate needs beyond the runner's own PATH (it calls
        // `hyprctl`): the socket of this compositor instance. Quickshell's own
        // environment carries it; `Quickshell.env(name)` reads one variable.
        env: ({ "HYPRLAND_INSTANCE_SIGNATURE": Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") })
        onLine: (s) => { root._output += s + "\n"; }
        onExited: (code, status) => {
            _timeout.stop();
            // 0 raised, 1 nothing to raise (a label that is not an "Open ...",
            // or no window for this app), 2 a real problem — only that one warns.
            if (code === 2) console.warn("[TrayRaise] window-activate failed:", root._output.trim());
            else if (code === 0) console.log("[TrayRaise]", root._output.trim());
        }
    }

    property Timer _timeout: Timer {
        id: _timeout
        interval: 4000
        onTriggered: {
            if (_raise.running) {
                console.warn("[TrayRaise] window-activate did not finish, killing it");
                _raise.stop();
            }
        }
    }
}
