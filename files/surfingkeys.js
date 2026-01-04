const {
    map,
    mapkey,
    vmapkey,
    unmap,
    addSearchAlias,
    tabOpenLink,
    RUNTIME,
    Hints,
    Front,
    Normal,
    Clipboard
} = api;

// --- General Settings ---
settings.hintAlign = "left";
settings.hintCharacters = "qwerasdf";
settings.smoothScroll = false;
settings.scrollStepSize = 140;
settings.omnibarPosition = "bottom";
settings.focusFirstCandidate = true;

// --- Site Specific Blacklist ---
settings.blacklistPattern = /.*((localhost|127\.0\.0\.1|github\.dev|figma\.com|mail\.google\.com).*)?/;

// --- Theme (Ashen / Flight Dark Adaptation) ---
const colors = {
    bg: "#020202",
    fg: "#6C7E96",
    accent: "#367bbf",
    accentBg: "#0d1824",
    hint: "#287373",
    hintText: "#FFFFFF",
    url: "#6096BF",
    match: "#DBC3FF",
    border: "#1c334e"
};

settings.theme = `
.sk_theme {
    font-family: "Iosevka", "Input Sans Condensed", "JetBrains Mono", sans-serif;
    font-size: 10pt;
    background: ${colors.bg};
    color: ${colors.fg};
}
.sk_theme tbody { color: ${colors.fg}; }
.sk_theme input { color: #d0d0d0; }
.sk_theme .url { color: ${colors.url}; }
.sk_theme .annotation { color: ${colors.hint}; }
.sk_theme .omnibar_highlight { color: ${colors.match}; font-weight: bold; }
.sk_theme .omnibar_timestamp { color: ${colors.accent}; }
.sk_theme .omnibar_visitcount { color: ${colors.hint}; }

.sk_theme #sk_omnibarSearchResult ul li:nth-child(odd) { background: #071526; }
.sk_theme #sk_omnibarSearchResult ul li.focused { background: ${colors.accentBg}; border-left: 2px solid ${colors.accent}; }

/* Hints */
#sk_hints > div {
    font-family: "Iosevka", "JetBrains Mono", monospace !important;
    background: ${colors.hint} !important;
    border: 1px solid ${colors.border} !important;
    color: ${colors.hintText} !important;
    box-shadow: 0px 2px 4px rgba(0,0,0,0.5);
    font-weight: bold;
}
#sk_hints > div[style*="background"] { 
    /* The active hint char matches */
    color: ${colors.hintText} !important;
    background: ${colors.accent} !important; 
}

#sk_status, #sk_find { font-size: 12pt; border: 1px solid ${colors.border}; background: ${colors.bg}; }
`;

// --- Keybindings ---

// Copy URL / Yanking
map('Y', 'yf'); // Y -> Copy Link (with hints)
mapkey('y', 'Copy current URL', function () {
    Clipboard.write(window.location.href);
    Front.showBanner("Copied: " + window.location.href);
});
// Copy as Markdown
mapkey('ym', 'Copy current title and URL as Markdown', function () {
    const md = `[${document.title}](${window.location.href})`;
    Clipboard.write(md);
    Front.showBanner("Copied Markdown: " + md);
});

// Tab Management
map('d', 'x');        // d -> Close Tab
map('u', 'X');        // u -> Restore Closed Tab
map('w', 'T');        // w -> Select Buffer (Tab list)

// Tab Navigation
map('J', 'E');        // J -> Prev Tab
map('K', 'R');        // K -> Next Tab
map('e', 'R');        // e -> Next Tab

// Tab Management (Advanced)
mapkey('gxR', 'Close tabs to the right', function () { RUNTIME("closeTabsToRight"); });
mapkey('gxL', 'Close tabs to the left', function () { RUNTIME("closeTabsToLeft"); });
mapkey('gxw', 'Close other tabs', function () { RUNTIME("closeOtherTabs"); });

// Video Speed
mapkey(']', 'Increase video speed', function () {
    const video = document.querySelector('video');
    if (video) {
        video.playbackRate += 0.25;
        Front.showBanner("Video speed: " + video.playbackRate);
    }
});
mapkey('[', 'Decrease video speed', function () {
    const video = document.querySelector('video');
    if (video) {
        video.playbackRate = Math.max(0.25, video.playbackRate - 0.25);
        Front.showBanner("Video speed: " + video.playbackRate);
    }
});

// Visual Mode Search Helpers
vmapkey('snp', 'Search Nix Packages', function () {
    const selection = window.getSelection().toString();
    tabOpenLink("https://search.nixos.org/packages?channel=unstable&query=" + encodeURIComponent(selection));
});
vmapkey('sno', 'Search Nix Options', function () {
    const selection = window.getSelection().toString();
    tabOpenLink("https://search.nixos.org/options?channel=unstable&query=" + encodeURIComponent(selection));
});

// --- Search Engines ---
// Standard
addSearchAlias('g', 'google', 'https://google.com/search?q=', 's', 'https://google.com/complete/search?client=chrome-omni&gs_ri=chrome-ext&oit=1&cp=1&pgcl=7&q=', function (response) {
    var res = JSON.parse(response.text);
    return res[1];
});
addSearchAlias('y', 'youtube', 'https://youtube.com/results?search_query=', 'y', 'https://clients1.google.com/complete/search?client=youtube&ds=yt&callback=cb&q=', function (response) {
    var match = response.text.match(/^[^(]*\((.*)\)$/);
    var res = JSON.parse(match ? match[1] : response.text);
    return res[1].map(function (d) { return d[0]; });
});
addSearchAlias('w', 'wikipedia', 'https://en.wikipedia.org/w/index.php?search={0}&title=Special%3ASearch');
addSearchAlias('gh', 'github', 'https://github.com/search?q=');
addSearchAlias('so', 'stackoverflow', 'https://stackoverflow.com/search?q=');

// NixOS Special
addSearchAlias('np', 'nix_packages', 'https://search.nixos.org/packages?channel=unstable&query=');
addSearchAlias('no', 'nix_options', 'https://search.nixos.org/options?channel=unstable&query=');
addSearchAlias('hm', 'home_manager', 'https://mipmip.github.io/home-manager-option-search/?query=');

// --- Quickmarks ---
mapkey('oA', 'Open ArtStation', function () { location.href = "https://magazine.artstation.com/"; });
mapkey('oE', 'Open ProjectEuler', function () { location.href = "https://projecteuler.net/"; });
mapkey('oL', 'Open LibGen', function () { location.href = "https://libgen.li"; });
mapkey('oc', 'Open Twitch Cooller', function () { location.href = "https://twitch.tv/cooller"; });
mapkey('og', 'Open Gmail', function () { location.href = "https://gmail.com"; });
mapkey('oh', 'Open SciHub', function () { location.href = "https://sci-hub.hkvisa.net/"; });
mapkey('ok', 'Open Reddit MechKeys', function () { location.href = "https://reddit.com/r/MechanicalKeyboards/"; });
mapkey('ol', 'Open LastFM', function () { location.href = "https://last.fm/user/e7z0x1"; });
mapkey('os', 'Open Steam Store', function () { location.href = "https://store.steampowered.com"; });
mapkey('ou', 'Open Reddit UnixPorn', function () { location.href = "https://reddit.com/r/unixporn"; });
mapkey('ov', 'Open VK', function () { location.href = "https://vk.com"; });
mapkey('oy', 'Open YouTube', function () { location.href = "https://youtube.com/"; });
mapkey('oz', 'Open Z-Lib', function () { location.href = "https://z-lib.is"; });
