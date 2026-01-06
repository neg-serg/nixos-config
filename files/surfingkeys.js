// Surfingkeys configuration
// https://github.com/brookhong/Surfingkeys

// ========== Settings ==========
settings.hintAlign = "left";
settings.hintCharacters = "asdfghjkl";
settings.omnibarSuggestion = true;
settings.focusFirstCandidate = true;
settings.scrollStepSize = 120;
settings.smoothScroll = true;
settings.modeAfterYank = "Normal";

// ========== Theme ==========
settings.theme = `
:root {
  --font: "Inter", "SF Pro Display", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, sans-serif;
  --font-mono: "JetBrains Mono", "Fira Code", "SF Mono", Monaco, Consolas, monospace;
  --font-size: 14px;
  --bg: #1e1e2e;
  --bg-dark: #181825;
  --bg-light: #313244;
  --fg: #cdd6f4;
  --fg-muted: #a6adc8;
  --accent: #89b4fa;
  --accent-hover: #b4befe;
  --border: #45475a;
  --green: #a6e3a1;
  --yellow: #f9e2af;
  --red: #f38ba8;
  --shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
}

/* Global styles */
body {
  font-family: var(--font);
  font-size: var(--font-size);
}

/* Hints */
.sk_theme {
  font-family: var(--font);
  font-size: var(--font-size);
  background: var(--bg);
  color: var(--fg);
}

#sk_hints .begin {
  color: var(--accent) !important;
}

#sk_hints .pending {
  color: var(--fg-muted) !important;
}

#sk_hints > div {
  font-family: var(--font-mono);
  font-size: 13px;
  font-weight: bold;
  padding: 4px 6px;
  background: var(--bg);
  color: var(--accent);
  border: 1px solid var(--border);
  border-radius: 4px;
  box-shadow: var(--shadow);
}

/* Omnibar */
#sk_omnibar {
  width: 50%;
  left: 25%;
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 8px !important;
  box-shadow: var(--shadow) !important;
  overflow: hidden;
}

#sk_omnibarSearchArea {
  background: var(--bg-dark) !important;
  border-bottom: 1px solid var(--border) !important;
  padding: 12px 16px !important;
  margin: 0 !important;
}

#sk_omnibarSearchArea input {
  font-family: var(--font) !important;
  font-size: 16px !important;
  color: var(--fg) !important;
  background: transparent !important;
}

#sk_omnibarSearchArea .prompt {
  color: var(--accent) !important;
  font-weight: bold !important;
}

#sk_omnibarSearchArea .separator {
  color: var(--border) !important;
}

#sk_omnibarSearchResult {
  margin: 0 !important;
  max-height: 60vh;
  overflow-y: auto;
}

#sk_omnibarSearchResult > ul {
  padding: 8px !important;
  margin: 0 !important;
}

#sk_omnibarSearchResult li {
  padding: 10px 12px !important;
  margin: 2px 0 !important;
  border-radius: 6px !important;
  background: transparent !important;
}

#sk_omnibarSearchResult li.focused {
  background: var(--bg-light) !important;
}

#sk_omnibarSearchResult li .title {
  color: var(--fg) !important;
  font-weight: 500 !important;
}

#sk_omnibarSearchResult li .url {
  color: var(--fg-muted) !important;
  font-size: 12px !important;
}

/* Status bar / Banner */
#sk_banner {
  font-family: var(--font);
  font-size: var(--font-size);
  background: var(--bg);
  color: var(--fg);
  border: 1px solid var(--border);
  border-radius: 6px;
  box-shadow: var(--shadow);
  padding: 8px 16px;
}

/* Keystroke help */
#sk_keystroke {
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 6px !important;
  box-shadow: var(--shadow) !important;
  padding: 12px !important;
}

#sk_keystroke kbd {
  font-family: var(--font-mono);
  font-size: 13px;
  color: var(--accent);
  background: var(--bg-light);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 2px 6px;
  margin: 2px;
  box-shadow: none;
}

#sk_keystroke .annotation {
  color: var(--fg);
  font-family: var(--font);
}

#sk_keystroke .candidates {
  color: var(--yellow) !important;
}

/* Status line */
#sk_status {
  font-family: var(--font);
  font-size: 12px;
  background: var(--bg-dark);
  color: var(--fg);
  border: 1px solid var(--border);
  border-radius: 4px;
  right: 10px !important;
  bottom: 10px !important;
}

#sk_status > span {
  padding: 4px 8px;
}

/* Rich hints */
.expandRichHints {
  animation: none;
}

.collapseRichHints {
  animation: none;
}

/* Visual mode */
#sk_find {
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 6px !important;
}

#sk_find input {
  font-family: var(--font) !important;
  color: var(--fg) !important;
  background: transparent !important;
}
`;

// ========== Smart Omnibar ==========
const smartDispatch = (input, newTab) => {
  const isURL = input.includes(".") && !input.includes(" ");
  if (isURL) {
    const url = input.match(/^https?:\/\//) ? input : "https://" + input;
    if (newTab) {
      api.tabOpenLink(url);
    } else {
      window.location.href = url;
    }
  } else {
    // Note: 'd' alias must match what is defined in addSearchAlias below
    const searchURL = "https://duckduckgo.com/?q=" + encodeURIComponent(input);
    if (newTab) {
      api.tabOpenLink(searchURL);
    } else {
      window.location.href = searchURL;
    }
  }
};

api.mapkey("t", "Smart Omnibar (New Tab)", () => {
  api.Front.openOmnibar({
    type: "SearchEngine",
    extra: "d",
    onEnter: (input) => smartDispatch(input, true),
  });
});

api.mapkey("o", "Smart Omnibar (Current Tab)", () => {
  api.Front.openOmnibar({
    type: "SearchEngine",
    extra: "d",
    onEnter: (input) => smartDispatch(input, false),
  });
});

api.mapkey("O", "Smart Omnibar (New Tab)", () => {
  api.Front.openOmnibar({
    type: "SearchEngine",
    extra: "d",
    onEnter: (input) => smartDispatch(input, true),
  });
});

// ========== Mappings ==========
// Scroll
api.map('j', 'j');
api.map('k', 'k');

// Large Scroll (Half Page)
api.mapkey('b', 'Scroll half page down', () => {
  api.Normal.scroll("pageDown");
});
api.mapkey('v', 'Scroll half page up', () => {
  api.Normal.scroll("pageUp");
});

// Tabs
api.map('E', 'E');  // Previous tab
api.map('e', 'R');  // Next tab
api.mapkey('d', 'Close current tab', function () {
  api.RUNTIME("closeTab");
});
api.map('u', 'X');  // Restore tab
api.map('w', 'T');  // Tab list

// History
api.map('H', 'S');  // Back
api.map('L', 'D');  // Forward

// Open links
api.map('F', 'gf'); // Open link in new tab

// Clipboard
api.map('yy', 'yy');
api.map('yl', 'yl');

// Video speed
api.mapkey(']', 'Increase video speed', function () {
  const video = document.querySelector('video');
  if (video) {
    video.playbackRate += 0.25;
    api.Front.showBanner("Speed: " + video.playbackRate.toFixed(2) + "x");
  }
});
api.mapkey('[', 'Decrease video speed', function () {
  const video = document.querySelector('video');
  if (video) {
    video.playbackRate = Math.max(0.25, video.playbackRate - 0.25);
    api.Front.showBanner("Speed: " + video.playbackRate.toFixed(2) + "x");
  }
});

// Search engines
api.addSearchAlias('g', 'Google', 'https://www.google.com/search?q=');
api.addSearchAlias('d', 'DuckDuckGo', 'https://duckduckgo.com/?q=');
api.addSearchAlias('y', 'YouTube', 'https://www.youtube.com/results?search_query=');
api.addSearchAlias('w', 'Wikipedia', 'https://en.wikipedia.org/wiki/Special:Search?search=');
api.addSearchAlias('gh', 'GitHub', 'https://github.com/search?q=');
api.addSearchAlias('aw', 'Arch Wiki', 'https://wiki.archlinux.org/index.php?search=');
api.addSearchAlias('np', 'npm', 'https://www.npmjs.com/search?q=');

// ========== Quickmarks ==========
const quickmarks = {
  'A': { name: 'ArtStation', url: 'https://magazine.artstation.com/' },
  'E': { name: 'ProjectEuler', url: 'https://projecteuler.net/' },
  'L': { name: 'LibGen', url: 'https://libgen.li' },
  'c': { name: 'Twitch Cooller', url: 'https://twitch.tv/cooller' },
  'g': { name: 'Gmail', url: 'https://gmail.com' },
  'h': { name: 'SciHub', url: 'https://sci-hub.hkvisa.net/' },
  'k': { name: 'Reddit MechKeys', url: 'https://reddit.com/r/MechanicalKeyboards/' },
  'l': { name: 'LastFM', url: 'https://last.fm/user/e7z0x1' },
  's': { name: 'Steam Store', url: 'https://store.steampowered.com' },
  'u': { name: 'Reddit UnixPorn', url: 'https://reddit.com/r/unixporn' },
  'v': { name: 'VK', url: 'https://vk.com' },
  'y': { name: 'YouTube', url: 'https://youtube.com/' },
  'z': { name: 'Z-Lib', url: 'https://z-lib.is' }
};

Object.entries(quickmarks).forEach(([key, site]) => {
  // Current tab (prefix 'o')
  api.mapkey('o' + key, 'Open ' + site.name, () => {
    location.href = site.url;
  });
  // New tab (prefix 'gn' for "Go New")
  api.mapkey('gn' + key, 'Open ' + site.name + ' in new tab', () => {
    api.tabOpenLink(site.url);
  });
});

// ========== Site-specific ==========
// Disable Surfingkeys on certain sites
settings.blocklistPattern = /mail\.google\.com|docs\.google\.com|discord\.com/i;
