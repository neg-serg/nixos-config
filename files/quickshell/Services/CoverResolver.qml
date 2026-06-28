import QtQuick
import Quickshell
import Quickshell.Io
import qs.Components
import qs.Settings

// Validates MPRIS art URLs and overrides with higher-priority cover files.
// Sits between currentPlayer.trackArtUrl and MusicManager.coverUrl.
Item {
    id: root

    // ── Input ──
    property string rawArtUrl: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property var currentPlayer: null

    // ── Output ──
    property string resolvedCoverUrl: ""

    // ── Internal state ──
    property string _lastTrackKey: ""
    property string _lastRawUrl: ""
    property bool _resolving: false
    property string _pendingUrl: ""

    // ── Constants ──
    readonly property var _canonicalNames: ["cover", "front", "folder", "album"]
    readonly property var _imageExtensions: ["jpg", "jpeg", "png", "gif", "webp"]

    // ── URL / path helpers ──
    function pathFromUrl(u) {
        if (!u) return "";
        var s = String(u);
        if (s.startsWith("file://")) {
            try {
                return decodeURIComponent(s.replace(/^file:\/\//, ""));
            } catch (e) {
                _dbg("pathFromUrl decode error", e);
                return s.replace(/^file:\/\//, "");
            }
        }
        if (s.startsWith("/")) return s;
        return "";
    }

    function dirFromPath(p) {
        if (!p) return "";
        var idx = p.lastIndexOf("/");
        return idx > 0 ? p.substring(0, idx) : "";
    }

    function basenameNoExt(p) {
        if (!p) return "";
        var idx = p.lastIndexOf("/");
        var name = idx >= 0 ? p.substring(idx + 1) : p;
        var dot = name.lastIndexOf(".");
        return dot > 0 ? name.substring(0, dot).toLowerCase() : name.toLowerCase();
    }

    function extensionOf(name) {
        if (!name) return "";
        var dot = name.lastIndexOf(".");
        return dot > 0 ? name.substring(dot + 1).toLowerCase() : "";
    }

    function isCanonical(filename) {
        var base = basenameNoExt(filename);
        for (var i = 0; i < _canonicalNames.length; i++) {
            if (base === _canonicalNames[i]) return true;
        }
        return false;
    }

    function isImageFile(filename) {
        var ext = extensionOf(filename);
        for (var i = 0; i < _imageExtensions.length; i++) {
            if (ext === _imageExtensions[i]) return true;
        }
        return false;
    }

    function canonicalRank(filename) {
        var base = basenameNoExt(filename);
        for (var i = 0; i < _canonicalNames.length; i++) {
            if (base === _canonicalNames[i]) return i;
        }
        return _canonicalNames.length; // non-canonical = lowest priority
    }

    function pathToFileUrl(p) {
        return "file://" + p;
    }

    // ── Track identity ──
    function trackKey() {
        return (trackTitle || "") + "|" + (trackArtist || "");
    }

    // ── Debug logging ──
    function _dbg() {
        try {
            if (Settings.settings && Settings.settings.debugLogs) {
                var args = Array.prototype.slice.call(arguments);
                console.debug("[CoverResolver]", args.join(" "));
            }
        } catch (e) { /* settings not ready */ }
    }

    // ── Debounce timer ──
    Timer {
        id: resolveDebounce
        interval: Theme.mediaArtDebounceMs
        repeat: false
        onTriggered: root._doResolve()
    }

    // ── Main resolve trigger ──
    onRawArtUrlChanged: _scheduleResolve()
    onTrackTitleChanged: _scheduleResolve()
    onTrackArtistChanged: _scheduleResolve()

    // Player switch detection
    onCurrentPlayerChanged: {
        // Cancel in-flight scan and reset state
        dirScanner.stop();
        _resolving = false;
        _lastTrackKey = "";
        _lastRawUrl = "";
        _scheduleResolve();
    }

    function _scheduleResolve() {
        var url = rawArtUrl || "";

        // Immediate clear on empty URL (player disconnect / stop)
        if (!url) {
            resolveDebounce.stop();
            dirScanner.stop();
            _resolving = false;
            _lastRawUrl = "";
            _lastTrackKey = trackKey();
            resolvedCoverUrl = "";
            _dbg("cleared (empty URL)");
            return;
        }

        // Debounce to coalesce rapid changes
        _pendingUrl = url;
        resolveDebounce.restart();
    }

    function _doResolve() {
        var url = _pendingUrl || rawArtUrl || "";
        if (!url) {
            resolvedCoverUrl = "";
            return;
        }

        var tk = trackKey();
        var trackChanged = (tk !== _lastTrackKey);
        _lastTrackKey = tk;

        // Non-file URLs (HTTP etc.) — pass through, add cache buster on track change
        if (!url.startsWith("file://")) {
            _lastRawUrl = url;
            resolvedCoverUrl = trackChanged ? _bustCache(url) : url;
            _dbg("pass-through (non-file URL):", url);
            return;
        }

        var localPath = pathFromUrl(url);
        if (!localPath) {
            resolvedCoverUrl = url;
            _dbg("pass-through (empty path from URL)");
            return;
        }

        // If the file is already a canonical cover name, pass through
        if (isCanonical(localPath)) {
            _lastRawUrl = url;
            resolvedCoverUrl = trackChanged ? _bustCache(url) : url;
            _dbg("pass-through (canonical):", basenameNoExt(localPath));
            return;
        }

        // Non-canonical — scan the directory for a better match
        var dir = dirFromPath(localPath);
        if (!dir) {
            resolvedCoverUrl = trackChanged ? _bustCache(url) : url;
            _dbg("pass-through (no dir)");
            return;
        }

        _dbg("scanning directory:", dir);
        _resolving = true;
        _lastRawUrl = url;
        dirScanner.targetDir = dir;
        dirScanner.fallbackUrl = url;
        dirScanner.isTrackChange = trackChanged;
        dirScanner._buf = [];
        dirScanner.cmd = ["ls", "-1", dir];
        dirScanner.start();
    }

    // ── Cache busting ──
    function _bustCache(url) {
        // Strip existing cache buster
        var base = String(url).replace(/\?t=\d+$/, "");
        return base + "?t=" + Date.now();
    }

    // ── Directory scanner ──
    ProcessRunner {
        id: dirScanner
        property string targetDir: ""
        property string fallbackUrl: ""
        property bool isTrackChange: false
        property var _buf: []
        autoStart: false
        restartOnExit: false
        restartMode: "never"

        onLine: (s) => {
            var name = (s || "").trim();
            if (name && root.isImageFile(name)) {
                _buf.push(name);
            }
        }

        onExited: (code, status) => {
            root._resolving = false;

            if (code !== 0 || _buf.length === 0) {
                root._dbg("scan failed or empty, fallback:", fallbackUrl);
                root.resolvedCoverUrl = isTrackChange ? root._bustCache(fallbackUrl) : fallbackUrl;
                return;
            }

            // Find the highest-priority canonical image
            var bestFile = null;
            var bestRank = root._canonicalNames.length;
            for (var i = 0; i < _buf.length; i++) {
                var rank = root.canonicalRank(_buf[i]);
                if (rank < bestRank) {
                    bestRank = rank;
                    bestFile = _buf[i];
                }
            }

            if (bestFile !== null) {
                var betterUrl = root.pathToFileUrl(targetDir + "/" + bestFile);
                root._dbg("override:", bestFile, "(rank", bestRank + ")");
                root.resolvedCoverUrl = isTrackChange ? root._bustCache(betterUrl) : betterUrl;
            } else {
                root._dbg("no canonical match, fallback:", fallbackUrl);
                root.resolvedCoverUrl = isTrackChange ? root._bustCache(fallbackUrl) : fallbackUrl;
            }
        }
    }

    Component.onCompleted: {
        if (rawArtUrl) _scheduleResolve();
    }
}
