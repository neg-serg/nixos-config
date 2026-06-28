function isPlayerMpd(player) {
    try {
        var p = player;
        if (!p) return false;
        var idStr    = String((p.service || p.busName || "")).toLowerCase();
        var nameStr  = String(p.name || "").toLowerCase();
        var identStr = String(p.identity || "").toLowerCase();
        var re = /(mpd|mpdris|mopidy|music\s*player\s*daemon)/;
        return re.test(idStr) || re.test(nameStr) || re.test(identStr);
    } catch (e) { console.warn("[MusicIds.isPlayerMpd]", e); return false; }
}

var MusicIds = {
    isPlayerMpd: isPlayerMpd
};
