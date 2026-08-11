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
settings.tabsThreshold = 0;

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
  color: #89cdd2 !important;
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

/* Omnibar / Tab list (T command) */
#sk_omnibar {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}

#sk_omnibar .omnibar_tab {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border-bottom: 1px solid var(--border) !important;
  padding: 4px 8px !important;
}

#sk_omnibar .omnibar_tab:hover,
#sk_omnibar .omnibar_tab:focus {
  background: var(--bg-highlight) !important;
}

#sk_omnibar .omnibar_tab .title {
  color: var(--fg) !important;
}

#sk_omnibar .omnibar_tab .url {
  color: var(--fg-muted) !important;
}

#sk_omnibar .omnibar_tab span {
  color: var(--accent) !important;
}

#sk_omnibar input {
  font-family: var(--font-mono) !important;
  font-size: var(--font-size) !important;
  color: var(--fg) !important;
  background: var(--hint-bg) !important;
  border: 1px solid var(--border) !important;
  padding: 6px 8px !important;
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

// Map 't' to open a fresh new tab via browser API (no server required)
api.mapkey('t', 'Open new tab', function () {
  api.tabOpenLink('about:newtab');
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
// Vim classic: Ctrl-[ as Esc
api.map('<Ctrl-[>', '<Esc>');

// Large Scroll (Half Page)
api.mapkey('b', 'Scroll half page down', () => {
  api.Normal.scroll("pageDown");
});
api.mapkey('v', 'Scroll half page up', () => {
  api.Normal.scroll("pageUp");
});

// e — next tab (gt)
api.unmap('e');  // Default: scroll page up
api.map('e', 'gt');

// Tabs
api.unmap('E');  // Default: scroll page down
api.map('E', 'gT');  // Previous tab
api.mapkey('d', 'Close current tab', function () {
  api.RUNTIME('closeTab');
});
api.map('u', 'X');  // Restore tab
api.map('w', 'T');  // Tab list

// o — native Ctrl+L (focus browser address bar) via native messaging server
api.mapkey('o', 'Focus address bar (native Ctrl-L)', function() {
  fetch('http://localhost:18888/addressbar');
});

// Disable SurfingKeys own UI menus (poor autocomplete). w-related kept.
api.unmap(':');   // Commands omnibar
api.unmap('A');   // LLM chat omnibar
api.unmap('Q');   // Word translation popup
api.unmap('go');  // Open URL in current tab
api.unmap('oh');  // Open URL from history
api.unmap('om');  // Open VIMarks
api.unmap('ab');  // Add bookmark
api.unmap(';x');  // Close tabs by URL
api.unmap(';gt'); // Gather filtered tabs into current window
api.unmap(';u');  // Edit URL with vim editor (history autocomplete)
api.unmap('?');   // Show usage popup
// Remaining search aliases via o (now freed)
api.unmap('os');  // stackoverflow search
api.unmap('ob');  // baidu search
api.unmap('oe');  // wikipedia search

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
  // Open in current tab (prefix J — free in SurfingKeys defaults)
  api.mapkey('J' + key, 'Open ' + site.name, () => {
    window.location.href = site.url;
  });
  // Open in new tab (prefix , — free in SurfingKeys defaults; 'gn' is taken by net-internals)
  api.mapkey(',' + key, 'Open ' + site.name + ' in new tab', () => {
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

// ========== Proxy ==========
// — Toggle: ;pt  switches between direct ↔ always (on/off)
// — Individual: ;pd direct, ;pa always, ;pb byhost, ;ps system, ;pc clear
api.mapkey(';pt', 'Toggle proxy on/off (direct ↔ always)', function() {
    api.RUNTIME('getSettings', {key: ['proxyMode']}, function(resp) {
        var current = resp.settings.proxyMode;
        var next = (current === 'always') ? 'direct' : 'always';
        api.RUNTIME('updateProxy', {mode: next}, function(rs) {
            api.Front.showBanner('Proxy: ' + rs.proxyMode);
        });
    });
});
api.map(';pd', ':setProxyMode direct', 0, 'Proxy: direct (no proxy)');
api.map(';pa', ':setProxyMode always', 0, 'Proxy: always (all sites)');
api.map(';pb', ':setProxyMode byhost', 0, 'Proxy: byhost (selected sites)');
api.map(';ps', ':setProxyMode system', 0, 'Proxy: system');
api.map(';pc', ':setProxyMode clear', 0, 'Proxy: clear (no control)');


// ========== Omnibar Search Engines (ported from b0o/surfingkeys-conf) ==========
// Hybrid mode: a<alias> opens the SurfingKeys omnibar overlay with the engine
// (awp = Wikipedia, agh = GitHub, ...); ca<alias> searches clipboard contents.
// Native address bar and 'o' are untouched. skipMaps keeps 'o<alias>' unbound.

const escHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]
  );

const skItem = (props) => (strings, ...vals) => ({
  html: strings.reduce(
    (acc, s, i) => acc + s + (i < vals.length ? escHtml(vals[i]) : ''),
    ''
  ),
  props,
});

const skUrlItem = (title, url) =>
  skItem({ url: url, query: title })`
    <div>
      <div style="font-weight: bold">${title}</div>
      <div style="opacity: 0.7; line-height: 1.3em">${url}</div>
    </div>
  `;

const ddgIcon = (domain) => `https://icons.duckduckgo.com/ip3/${domain}.ico`;

const skEngines = [
  {
    alias: 'wp', name: 'wikipedia',
    search: 'https://en.wikipedia.org/w/index.php?search=',
    compl: 'https://en.wikipedia.org/w/api.php?action=query&format=json&generator=prefixsearch&prop=info|pageprops%7Cpageimages%7Cdescription&redirects=&ppprop=displaytitle&piprop=thumbnail&pithumbsize=100&pilimit=6&inprop=url&gpssearch=',
    favicon: ddgIcon('en.wikipedia.org'),
    cb: (r) => Object.values(JSON.parse(r.text).query.pages).map((p) =>
      skItem({ url: p.fullurl })`
        <div style="padding:5px;display:grid;grid-template-columns:60px 1fr;grid-gap:15px">
          <img style="width:60px" src="${p.thumbnail ? p.thumbnail.source : ''}">
          <div>
            <div class="title"><strong>${p.title}</strong></div>
            <div class="title">${p.description ?? ''}</div>
          </div>
        </div>
      `),
  },
  {
    alias: 'gh', name: 'github',
    search: 'https://github.com/search?q=',
    compl: 'https://api.github.com/search/repositories?sort=stars&order=desc&q=',
    favicon: ddgIcon('github.com'),
    cb: (r) => JSON.parse(r.text).items.map((s) => {
      const stars = s.stargazers_count ? `[★${s.stargazers_count}] ` : '';
      return skUrlItem(stars + s.full_name, s.html_url);
    }),
  },
  {
    alias: 'yt', name: 'youtube',
    search: 'https://www.youtube.com/results?search_query=',
    compl: 'https://suggestqueries.google.com/complete/search?client=youtube&ds=yt&q=',
    favicon: ddgIcon('youtube.com'),
    cb: (r) => JSON.parse(r.text)[1],
  },
  {
    alias: 'du', name: 'duckduckgo',
    search: 'https://duckduckgo.com/?q=',
    compl: 'https://duckduckgo.com/ac/?q=',
    favicon: ddgIcon('duckduckgo.com'),
    cb: (r) => JSON.parse(r.text).map((x) => x.phrase),
  },
  {
    alias: 'D', name: 'duckduckgo-lucky',
    search: 'https://duckduckgo.com/?q=\\',
    compl: 'https://duckduckgo.com/ac/?q=\\',
    favicon: ddgIcon('duckduckgo.com'),
    cb: (r) => JSON.parse(r.text).map((x) => x.phrase),
  },
  {
    alias: 'go', name: 'google',
    search: 'https://www.google.com/search?q=',
    compl: 'https://www.google.com/complete/search?client=chrome-omni&gs_ri=chrome-ext&oit=1&cp=1&pgcl=7&q=',
    favicon: ddgIcon('www.google.com'),
    cb: (r) => JSON.parse(r.text)[1],
  },
  {
    alias: 'so', name: 'stackoverflow',
    search: 'https://stackoverflow.com/search?q=',
    compl: 'https://api.stackexchange.com/2.2/search/advanced?pagesize=10&order=desc&sort=relevance&site=stackoverflow&q=',
    favicon: ddgIcon('stackoverflow.com'),
    cb: (r) => JSON.parse(r.text).items.map((s) => skUrlItem(`[${s.score}] ${s.title}`, s.link)),
  },
  {
    alias: 're', name: 'reddit',
    search: 'https://www.reddit.com/search?sort=relevance&t=all&q=',
    compl: 'https://api.reddit.com/search?syntax=plain&sort=relevance&limit=20&q=',
    favicon: ddgIcon('reddit.com'),
    cb: (r) => JSON.parse(r.text).data.children.map(({ data }) => {
      const thumb = String(data.thumbnail).startsWith('http') ? data.thumbnail : '';
      return skItem({ url: 'https://reddit.com' + data.permalink })`
        <div style="display: flex; flex-direction: row">
          <img style="width: 70px; height: 50px; margin-right: 0.8em" alt="thumbnail" src="${thumb}">
          <div>
            <strong>${data.title}</strong>
            <div style="opacity: 60%">↑${data.score} • r/${data.subreddit}</div>
          </div>
        </div>
      `;
    }),
  },
  {
    alias: 'aw', name: 'archwiki',
    search: 'https://wiki.archlinux.org/index.php?go=go&search=',
    compl: 'https://wiki.archlinux.org/api.php?action=opensearch&format=json&formatversion=2&namespace=0&limit=10&suggest=true&search=',
    favicon: ddgIcon('wiki.archlinux.org'),
    cb: (r) => JSON.parse(r.text)[1],
  },
  {
    alias: 'md', name: 'mdn',
    search: 'https://developer.mozilla.org/search?q=',
    compl: 'https://developer.mozilla.org/api/v1/search?q=',
    favicon: ddgIcon('developer.mozilla.org'),
    cb: (r) => JSON.parse(r.text).documents.map((s) =>
      skItem({ url: `https://developer.mozilla.org/${s.locale}/docs/${s.slug}` })`
        <div>
          <div class="title"><strong>${s.title}</strong></div>
          <div style="font-size:0.8em"><em>${s.slug}</em></div>
          <div>${s.summary}</div>
        </div>
      `),
  },
  {
    alias: 'nx', name: 'nixpkgs',
    search: 'https://search.nixos.org/packages?channel=unstable&query=',
    favicon: ddgIcon('search.nixos.org'),
  },
];

skEngines.forEach(({ alias, name, search, compl, favicon, cb }) => {
  api.addSearchAlias(alias, name, search, '', compl || '', cb, undefined, {
    favicon_url: favicon,
    skipMaps: true,
  });
  api.mapkey('a' + alias, `#8Search ${name}`, () =>
    api.Front.openOmnibar({ type: 'SearchEngine', extra: alias })
  );
  api.mapkey('ca' + alias, `#8Search ${name} with clipboard`, () =>
    api.Clipboard.read((c) =>
      api.Front.openOmnibar({ type: 'SearchEngine', pref: c.data, extra: alias })
    )
  );
});

// ========== Page Utilities (from b0o/surfingkeys-conf) ==========
// yT (duplicate tab) and gxt/gxT (close tabs left/right) are SurfingKeys defaults.

api.mapkey('yM', 'Copy page as Markdown link', () => {
  api.Clipboard.write(`[${document.title}](${window.location.href})`);
});

api.mapkey('=a', 'Open Wayback Machine for page', () => {
  api.tabOpenLink('https://web.archive.org/web/*/' + window.location.href);
});
api.mapkey('=o', 'Open outline.com version of page', () => {
  api.tabOpenLink('https://outline.com/' + window.location.href);
});
api.mapkey('=s', 'Open social discussions for page', () => {
  api.tabOpenLink('https://discussions.xojoc.pw/?url=' + encodeURIComponent(window.location.href));
});

api.map('gxE', 'gxt'); // Close tab to left (default gxt)
api.map('gxR', 'gxT'); // Close tab to right (default gxT)

api.mapkey('g.', 'Go to parent domain', () => {
  const subdomains = window.location.host.split('.');
  const parent = (subdomains.length > 2 ? subdomains.slice(1) : subdomains).join('.');
  api.tabOpenLink(window.location.protocol + '//' + parent);
});
