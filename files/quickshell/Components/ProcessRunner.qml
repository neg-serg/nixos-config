import QtQuick
import Quickshell.Io
import qs.Settings

// ProcessRunner: run a process (streaming lines or poll JSON) with backoff/poll timers.
// Examples: streaming — ProcessRunner { cmd: ["rsmetrx"], backoffMs: Theme.networkRestartBackoffMs, onLine: (l)=>handle(l) }
//           poll JSON — ProcessRunner { cmd: ["bash","-lc","ip -j -br a"], intervalMs: Theme.vpnPollMs, parseJson: true, onJson: (o)=>handle(o) }
Item {
    id: root
    property var cmd: []
    property int backoffMs: 1500
    property var env: null
    property int intervalMs: 0
    // Parse entire stdout as JSON once (on process end)
    property bool parseJson: false
    // Parse each line as JSON (streaming); falls back to line signal on parse failure
    property bool jsonLine: false
    // Debounce emission of line/jsonLine events (ms); 0 = emit immediately
    property int debounceMs: 0
    // Restart policy on exit when intervalMs == 0: 'always' or 'never'.
    // Backward-compat: if empty, fallback to restartOnExit boolean.
    property string restartMode: ""
    // Backward-compat flag (deprecated). Use restartMode instead.
    property bool restartOnExit: true
    property bool autoStart: true
    readonly property alias running: proc.running

    // STDIN support
    property bool stdinEnabled: false
    function write(data) { try { proc.write(String(data)) } catch (e) { /* proc may not be running */ } }
    function closeStdin() { try { proc.stdinEnabled = false } catch (e) { /* proc may not be running */ } }

    // Raw chunk mode (binary-like streaming)
    // When true, emit chunks of stdout via `chunk(string data)` instead of line/jsonLine logic.
    property bool rawMode: false
    signal chunk(string data)
    signal started()

    signal line(string s)
    signal json(var obj)
    signal exited(int code, int status)

    // stdout parsers.
    //
    // StdioCollector must never be used for streaming: with waitForEnd = false it
    // retains every byte ever received and re-decodes the whole buffer on each
    // `text` read, so a long-running stream costs O(n^2) CPU and O(n) memory.
    // Measured before this change: a 440 MB cava backlog pinned quickshell at
    // ~100% CPU and ~2 GB RSS, with 52% of all samples inside
    // StdioCollector -> QString::fromUtf8 -> QUtf8::convertToUnicode.
    // SplitParser drops its buffer after every chunk, so streaming stays
    // O(chunk); it is attached only when the whole output is not needed.
    StdioCollector {
        id: jsonStdout
        waitForEnd: true
        onStreamFinished: {
            if (!root.parseJson) return;
            try {
                const obj = JSON.parse(text);
                root.json(obj);
            } catch (e) { /* ignore parse errors */ }
        }
    }

    // Empty splitMarker => arbitrary chunks (raw/binary mode). "\n" => one
    // complete line per chunk, which also keeps multi-byte UTF-8 intact.
    SplitParser {
        id: streamStdout
        splitMarker: root.rawMode ? "" : "\n"
        onRead: (data) => root._handleChunk(data)
    }

    // stderr is not consumed by ProcessRunner; bound it so a chatty child cannot
    // grow the buffer without limit (a null parser would close the channel).
    SplitParser { splitMarker: "\n" }

    // Streaming chunk handler: raw bytes in rawMode, one complete line otherwise.
    function _handleChunk(data) {
        if (root.rawMode) {
            if (root.debounceMs > 0) {
                root._pendingLines.push(data);
                debounce.restart();
            } else {
                root.chunk(data);
            }
            return;
        }
        const s = String(data || "").trim();
        if (s.length === 0) return;
        root._pendingLines.push(s);
        if (root.debounceMs > 0) {
            debounce.restart();
        } else {
            root._flushPending();
        }
    }

    // Debounce buffer for streaming output
    property var _pendingLines: []
    Timer {
        id: debounce
        interval: Math.max(1, root.debounceMs)
        repeat: false
        onTriggered: root._flushPending()
    }

    // Restart backoff. `backoff.running` participates in the `running` binding
    // below instead of imperatively assigning `proc.running = true`: an
    // imperative assignment destroys the declarative binding, after which
    // `autoStart` is never re-evaluated and a stream keeps running after it
    // should have stopped (that is why cava streamed for 19 h with playback
    // stopped). Using `!backoff.running` keeps the backoff delay and survives
    // restarts.
    Timer {
        id: backoff
        interval: root.backoffMs
        repeat: false
    }

    Timer {
        id: poll
        interval: Math.max(0, root.intervalMs)
        repeat: root.intervalMs > 0
        running: root.intervalMs > 0 && root.autoStart
        onTriggered: if (!proc.running) proc.running = true
    }

    Process {
        id: proc
        command: root.cmd
        environment: (root.env && typeof root.env === 'object') ? root.env : ({})
        running: root.intervalMs === 0 ? (root.autoStart && !backoff.running) : false
        stdinEnabled: root.stdinEnabled
        onStarted: { root.started() }

        stdout: root.parseJson ? jsonStdout : streamStdout

        onExited: function(exitCode, exitStatus) {
            root.exited(exitCode, exitStatus);
            function _shouldRestart() {
                var m = String(root.restartMode || "").toLowerCase();
                if (m === 'always') return true;
                if (m === 'never') return false;
                // Fallback to legacy flag
                return !!root.restartOnExit;
            }
            if (root.intervalMs === 0 && _shouldRestart()) backoff.restart();
        }
    }

    function start() { proc.running = true }
    function stop()  { proc.running = false }

    function _flushPending() {
        if (!root._pendingLines || root._pendingLines.length === 0) return;
        try {
            if (root.rawMode) {
                // Join and emit as one chunk
                const data = root._pendingLines.join("");
                root.chunk(data);
            } else {
                for (let i = 0; i < root._pendingLines.length; i++) {
                    const s = root._pendingLines[i];
                    if (root.jsonLine) {
                        try {
                            const obj = JSON.parse(s);
                            root.json(obj);
                            continue;
                        } catch (e) { /* fall through to line */ }
                    }
                    root.line(s);
                }
            }
        } finally {
            root._pendingLines = [];
        }
    }
}
