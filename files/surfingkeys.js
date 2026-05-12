// Surfingkeys configuration
// https://github.com/brookhong/Surfingkeys

// ========== Settings ==========
settings.hintAlign = "left";
settings.hintCharacters = "asdfghjkl";
settings.omnibarSuggestion = false; // DISABLED: Using native address bar
settings.focusFirstCandidate = false;
settings.scrollStepSize = 120;
settings.smoothScroll = true;
settings.modeAfterYank = "Normal";

// ========== Theme ==========
settings.theme = `
:root {
  --font: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  --font-mono: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  --font-size: 0.875rem;
  --bg: #020202;
  --bg-highlight: #13384f;
  --fg: #f0f1ff;
  --fg-muted: rgba(240, 241, 255, 0.6);
  --accent: #89cdd2;
  --border: #0a3749;
  --hint-bg: #001742;
}

/* Global Reset */
.sk_theme {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  background: var(--bg);
  color: var(--fg);
}

.sk_theme tbody {
  color: var(--fg);
}

.sk_theme input {
  color: var(--fg);
}

/* Hints */
#sk_hints .begin {
  color: var(--accent) !important;
}

/* Status bar / Banner */
#sk_banner {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border);
  border-radius: 0;
  box-shadow: none;
  padding: 4px 12px;
}

/* Keystroke help */
#sk_keystroke {
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  padding: 6px !important;
  color: var(--fg) !important;
}

#sk_keystroke kbd {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
  color: var(--accent) !important;
  background: var(--hint-bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0;
  padding: 2px 4px;
  margin: 2px;
  box-shadow: none;
}

#sk_keystroke .annotation {
  color: var(--fg) !important;
}

#sk_keystroke .candidates {
  color: var(--accent) !important;
}

/* Status line */
#sk_status {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0;
}

#sk_status > span {
  padding: 4px 8px;
  color: var(--fg) !important;
  border-right: 1px solid var(--border);
}

/* Search Matches on Page */
.sk_find_highlight {
  background: var(--bg-highlight) !important;
  color: var(--fg) !important;
  border-bottom: 2px solid var(--accent) !important;
}

/* Search Bar (Visual Mode /) */
#sk_find {
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  color: var(--fg) !important;
}

#sk_find input {
  font-family: var(--font-mono) !important;
  font-weight: 600 !important;
  color: var(--fg) !important;
  background: transparent !important; 
  border: none !important;
}

/* Markdown/Misc Popups */
#sk_bubble {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}

#sk_usage {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}

#sk_usage .feature_name {
  color: var(--accent) !important;
  border-bottom: 2px solid var(--border) !important;
}

#sk_usage .feature_name > span {
  border-bottom: none !important;
}

#sk_popup {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}
`;

// ========== Hints Styling (Shadow DOM) ==========
api.Hints.style(`
  div, mask {
    font-family: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace !important;
    font-size: 0.875rem !important;
    font-weight: 600 !important;
    padding: 2px 4px !important;
    background: #001742 !important;
    background-image: none !important;
    color: #89cdd2 !important;
    border: 1px solid #0a3749 !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }
  
  mask {
    background: rgba(137, 205, 210, 0.3) !important;
    border: 1px solid #89cdd2 !important;
  }

  mask.activeInput {
    background: rgba(137, 205, 210, 0.6) !important;
    border: 2px solid #89cdd2 !important;
  }
`);

// Style for text/visual mode hints
api.Hints.style(`
  div {
    font-family: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace !important;
    font-size: 0.875rem !important;
    font-weight: 600 !important;
    padding: 2px 4px !important;
    background: #001742 !important;
    background-image: none !important;
    color: #89cdd2 !important;
    border: 1px solid #0a3749 !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }
  div.begin {
    color: #89cdd2 !important;
  }
`, "text");

// ========== Navigation ==========

// Unmap Omnibar-related default bindings to prevent accidental triggering
// Map 't' to Local Focus Server (bypassing Content Script restrictions)
api.mapkey('t', 'Focus Address Bar', function () {
  fetch('http://localhost:18888/focus')
    .then(r => {
      if (!r.ok) api.Front.showBanner("Focus Error: " + r.statusText);
    })
    .catch(e => {
      api.Front.showBanner("Focus Failed: Is surfingkeys-server running?");
      console.error(e);
    });
});

api.unmap('b');
api.unmap('og'); // default open google
api.unmap('od'); // default open duckduckgo
api.unmap('oy'); // default open youtube
api.unmap('ow');
api.unmap('on');
api.unmap('ox');

// Mapping for standard browsing
api.map('j', 'j');
api.map('k', 'k');

// Large Scroll (Half Page)
api.mapkey('b', 'Scroll half page down', () => {
  api.Normal.scroll("pageDown");
});
api.mapkey('v', 'Scroll half page up', () => {
  api.Normal.scroll("pageUp");
});

// Tabs (unmap default scroll first)
api.unmap('e');  // Default: scroll page up
api.unmap('E');  // Default: scroll page down
api.map('E', 'gT');  // Previous tab
api.map('e', 'R');  // Next tab (R is default next tab)
api.mapkey('d', 'Close current tab', function () {
  fetch('http://localhost:18888/close')
    .then(r => {
      if (!r.ok) api.Front.showBanner("Close Error: " + r.statusText);
    })
    .catch(e => {
      api.Front.showBanner("Close Failed: Is surfingkeys-server running?");
      console.error(e);
    });
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

// ========== Quickmarks (Using Native Tab Open) ==========
// Since we disabled Omnibar, we just open these directly in new tabs or current tab
// but without passing through the Omnibar UI.

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
  // Open in current tab
  api.mapkey('o' + key, 'Open ' + site.name, () => {
    window.location.href = site.url;
  });
  // Open in new tab
  api.mapkey('gn' + key, 'Open ' + site.name + ' in new tab', () => {
    api.tabOpenLink(site.url);
  });
});

// ========== Site-specific ==========

settings.blocklistPattern = /mail\.google\.com|docs\.google\.com|discord\.com|app\.slack\.com/i;

// ========== Image Download ==========
api.mapkey('zi', 'Download image without dialog', function() {
    api.Hints.create('img', function(element) {
        var src = element.src;
        api.RUNTIME('download', {
            url: src,
            saveAs: false
        });
    });
});

