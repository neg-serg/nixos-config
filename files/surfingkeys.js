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
  --font: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  --font-mono: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  --font-size: 0.875rem;
  --bg: #000000;
  --bg-highlight: #0d1824;
  --fg: #6c7e96;
  --fg-muted: #7387a1;
  --accent: #a5c1e6;
  --border: #223f73;
  --hint-bg: #1c334e;
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
  color: #a5c1e6 !important;
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
  background: var(--bg) !important;
  padding: 6px 8px !important;
}

/* ===== Full neg.nvim coverage of the frontend (.sk_theme defaults are light) ===== */
body {
  font-family: var(--font-mono) !important;
}

#sk_omnibarSearchArea {
  border-bottom: none !important;
}

.sk_theme .url {
  color: #7c90a8 !important;
}

.sk_theme .annotation {
  color: #607794 !important;
}

.sk_theme kbd {
  background: #0d1824 !important;
  color: #a5c1e6 !important;
  border: 1px solid #223f73 !important;
  border-radius: 3px !important;
  font-family: var(--font-mono) !important;
}

.sk_theme .frame {
  background: rgba(165, 193, 230, 0.06) !important;
  border: 1px solid #223f73 !important;
  border-radius: 8px !important;
}

.sk_theme .omnibar_highlight {
  color: #a5c1e6 !important;
  font-weight: 600;
}

.sk_theme .omnibar_folder {
  color: #7387a1 !important;
}

.sk_theme .omnibar_timestamp,
.sk_theme .omnibar_visitcount {
  color: #607794 !important;
}

.sk_theme .prompt,
.sk_theme .resultPage {
  color: #7387a1 !important;
}

.sk_theme .feature_name {
  color: #a5c1e6 !important;
}

.sk_theme .separator {
  color: #223f73 !important;
}

.sk_theme #sk_omnibarSearchResult>ul>li {
  color: #6c7e96 !important;
}

.sk_theme #sk_omnibarSearchResult>ul>li:nth-child(odd) {
  background: transparent !important;
}

.sk_theme #sk_omnibarSearchResult>ul>li.focused {
  background: #0d1824 !important;
}

.sk_theme #sk_omnibarSearchResult>ul>li.focused div.title {
  color: #e8f1ff !important;
}

.sk_theme #sk_omnibarSearchResult>ul>li.window {
  border: 1px solid #223f73 !important;
  border-radius: 8px !important;
}

.sk_theme #sk_omnibarSearchResult>ul>li.window.focused {
  border: 1px solid #4779b3 !important;
}

#sk_omnibarSearchResult li div.title {
  color: #8d9eb2;
}

#sk_omnibarSearchResult li div.url {
  color: #7387a1;
}

#sk_omnibarSearchResult li span.annotation {
  color: #607794;
}

.sk_theme div.table>* {
  color: #6c7e96;
}
`;

// ========== Hints Styling (Shadow DOM) ==========
api.Hints.style(`div, mask {
    font-family: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace !important;
    font-size: 12px !important;
    font-weight: 600 !important;
    padding: 1px 3px !important;
    background: #003b88 !important;
    background-image: none !important;
    color: #e8f1ff !important;
    border: 1px solid #4779b3 !important;
    border-radius: 4px !important;
    box-shadow: none !important;
  }
  
  mask {
    background: rgba(165, 193, 230, 0.3) !important;
    border: 1px solid #a5c1e6 !important;
  }

  mask.activeInput {
    background: rgba(165, 193, 230, 0.6) !important;
    border: 2px solid #a5c1e6 !important;
  }
`);

// Style for text/visual mode hints
api.Hints.style(`div {
    font-family: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace !important;
    font-size: 12px !important;
    font-weight: 600 !important;
    padding: 1px 3px !important;
    background: #003b88 !important;
    background-image: none !important;
    color: #e8f1ff !important;
    border: 1px solid #4779b3 !important;
    border-radius: 4px !important;
    box-shadow: none !important;
  }
  div.begin {
    color: #e8f1ff !important;
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
// s — scroll page down like Space (full viewport, instant)
api.mapkey('s', 'Scroll page down (like Space)', () => {
  window.scrollBy(0, window.innerHeight);
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
  'z': { name: 'Z-Lib', url: 'https://z-lib.is' },
  // Dev tools (ported from sf-config webDevOpener.js; the o* prefix is
  // shadowed by the custom 'o' address-bar mapping, so these are quickmarks)
  'b': { name: 'Localhost:5173', url: 'http://localhost:5173/' },
  'd': { name: 'DaisyUI (Vite)', url: 'https://daisyui.com/docs/install/vite/' },
  'm': { name: 'MongoDB Atlas', url: 'https://cloud.mongodb.com' },
  'n': { name: 'NextJS Docs', url: 'https://nextjs.org/docs' },
  'p': { name: 'Postman', url: 'https://web.postman.co/home' },
  't': { name: 'Tailwind (Vite)', url: 'https://tailwindcss.com/docs/installation/using-vite' }
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

// ========== Russian layout (ЙЦУКЕН) ==========
// SurfingKeys matches vim keys by event.key, so under the ru layout every
// latin-letter bind breaks. Map each Cyrillic letter to its Latin command
// (api.map rhs is a key sequence dispatched to the command handler, no DOM
// key event is re-created, so this cannot loop).
// Reference table: docs/howto/hotkeys-ru-layout.ru.md
const ru2en = { 'й':'q','ц':'w','у':'e','к':'r','е':'t','н':'y','г':'u','ш':'i','щ':'o','з':'p',
  'х':'[','ъ':']','ф':'a','ы':'s','в':'d','а':'f','п':'g','р':'h','о':'j','л':'k','д':'l',
  'ж':';','э':"'",'я':'z','ч':'x','с':'c','м':'v','и':'b','т':'n','ь':'m','б':',','ю':'.' };
Object.entries(ru2en).forEach(([ru, en]) => api.map(ru, en));


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
    compl: 'https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=',
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
  // NOTE: reddit blocks api.reddit.com from many IPs (returns HTML) — suggestions
  // may be empty; Enter still opens the normal reddit search page.
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
  {
    alias: 'no', name: 'nixos-options',
    search: 'https://search.nixos.org/options?channel=unstable&query=',
    favicon: ddgIcon('search.nixos.org'),
  },
  {
    alias: 'nw', name: 'nixos-wiki',
    search: 'https://nixos.wiki/index.php?search=',
    compl: 'https://nixos.wiki/api.php?action=opensearch&format=json&formatversion=2&namespace=0&limit=10&suggest=true&search=',
    favicon: ddgIcon('nixos.wiki'),
    cb: (r) => JSON.parse(r.text)[1],
  },
  {
    alias: 'hb', name: 'habr',
    search: 'https://habr.com/ru/search/?q=',
    favicon: ddgIcon('habr.com'),
  },
  {
    alias: 'on', name: 'opennet',
    search: 'https://www.opennet.ru/search.shtml?words=',
    favicon: ddgIcon('www.opennet.ru'),
  },
  {
    alias: 'lr', name: 'linux.org.ru',
    search: 'https://www.linux.org.ru/search.jsp?q=',
    favicon: ddgIcon('www.linux.org.ru'),
  },
  {
    alias: 'gl', name: 'gitlab',
    search: 'https://gitlab.com/search?search=',
    favicon: ddgIcon('gitlab.com'),
  },
  {
    alias: 'np', name: 'npm',
    search: 'https://www.npmjs.com/search?q=',
    compl: 'https://api.npms.io/v2/search/suggestions?size=20&q=',
    favicon: ddgIcon('www.npmjs.com'),
    cb: (r) => JSON.parse(r.text).map((s) =>
      skItem({ url: s.package.links.npm })`
        <div>
          <div class="title"><strong>${s.highlight}</strong> <span style="font-size:0.8em">v${s.package.version}</span></div>
          <div>${s.package.description ?? ''}</div>
        </div>
      `),
  },
  {
    alias: 'rc', name: 'crates',
    search: 'https://crates.io/search?q=',
    compl: 'https://crates.io/api/v1/crates?t=0&q=',
    favicon: ddgIcon('crates.io'),
    cb: (r) => JSON.parse(r.text).crates.map((s) => {
      const meta = (s.downloads ? `[↓${s.downloads}] ` : '') + (s.max_version ? `[v${s.max_version}] ` : '');
      return skItem({ url: `https://crates.io/crates/${s.name}` })`
        <div>
          <div class="title"><strong>${s.name}</strong> ${meta}</div>
          <div>${s.description ?? ''}</div>
        </div>
      `;
    }),
  },
  {
    alias: 'hn', name: 'hackernews',
    search: 'https://hn.algolia.com/?query=',
    compl: 'https://hn.algolia.com/api/v1/search?tags=(story,comment)&query=',
    favicon: ddgIcon('news.ycombinator.com'),
    cb: (r) => JSON.parse(r.text).hits.map((s) => {
      const prefix = (s.points ? `[↑${s.points}] ` : '') + (s.num_comments ? `[↲${s.num_comments}] ` : '');
      const title = s._tags[0] === 'story' ? s.title : (s._tags[0] === 'comment' ? s.comment_text : s.objectID);
      return skUrlItem(prefix + title, `https://news.ycombinator.com/item?id=${encodeURIComponent(s.objectID)}`);
    }),
  },
  {
    alias: 'dh', name: 'dockerhub',
    search: 'https://hub.docker.com/search?q=',
    compl: 'https://hub.docker.com/v2/search/repositories/?page_size=20&query=',
    favicon: ddgIcon('hub.docker.com'),
    cb: (r) => JSON.parse(r.text).results.map((s) => {
      const repo = s.repo_name.includes('/') ? s.repo_name : `_/${s.repo_name}`;
      return skItem({ url: `https://hub.docker.com/r/${repo}` })`
        <div>
          <div class="title"><strong>${repo}</strong></div>
          <div>[★${s.star_count}] [↓${s.pull_count}]</div>
          <div>${s.short_description ?? ''}</div>
        </div>
      `;
    }),
  },
  {
    alias: 'gi', name: 'google-images',
    search: 'https://www.google.com/search?tbm=isch&q=',
    compl: 'https://www.google.com/complete/search?client=chrome-omni&gs_ri=chrome-ext&oit=1&cp=1&pgcl=7&ds=i&q=',
    favicon: ddgIcon('www.google.com'),
    cb: (r) => JSON.parse(r.text)[1],
  },
  {
    alias: 'st', name: 'steam',
    search: 'https://store.steampowered.com/search/?term=',
    favicon: ddgIcon('store.steampowered.com'),
  },
  {
    alias: 'se', name: 'stackexchange',
    search: 'https://stackexchange.com/search?q=',
    compl: 'https://duckduckgo.com/ac/?q=!stackexchange%20',
    favicon: ddgIcon('stackexchange.com'),
    cb: (r) => JSON.parse(r.text).map((x) => x.phrase.replace(/^!stackexchange /, '')),
  },
  {
    alias: 'wt', name: 'wiktionary',
    search: 'https://en.wiktionary.org/w/index.php?search=',
    compl: 'https://en.wiktionary.org/w/api.php?action=query&format=json&generator=prefixsearch&gpssearch=',
    favicon: ddgIcon('en.wiktionary.org'),
    cb: (r) => Object.values(JSON.parse(r.text).query.pages).map((p) => p.title),
  },
  {
    alias: 'gs', name: 'google-scholar',
    search: 'https://scholar.google.com/scholar?q=',
    compl: 'https://scholar.google.com/scholar_complete?q=',
    favicon: ddgIcon('scholar.google.com'),
    cb: (r) => JSON.parse(r.text).l,
  },
  {
    alias: 'di', name: 'duckduckgo-images',
    search: 'https://duckduckgo.com/?ia=images&iax=images&q=',
    compl: 'https://duckduckgo.com/ac/?ia=images&iax=images&q=',
    favicon: ddgIcon('duckduckgo.com'),
    cb: (r) => JSON.parse(r.text).map((x) => x.phrase),
  },
  {
    alias: 'dv', name: 'duckduckgo-videos',
    search: 'https://duckduckgo.com/?ia=videos&iax=videos&q=',
    compl: 'https://duckduckgo.com/ac/?ia=videos&iax=videos&q=',
    favicon: ddgIcon('duckduckgo.com'),
    cb: (r) => JSON.parse(r.text).map((x) => x.phrase),
  },
  {
    alias: 'hf', name: 'huggingface',
    search: 'https://huggingface.co/models?search=',
    compl: 'https://huggingface.co/api/quicksearch?q=',
    favicon: ddgIcon('huggingface.co'),
    cb: (r) => {
      const res = JSON.parse(r.text);
      return [
        ...res.models.map((m) => skItem({ url: `https://huggingface.co/${m.id}` })`
          <div>
            <div><strong>${m.id}</strong></div>
            <div><span style="font-size: 0.9em; opacity: 70%">model</span></div>
          </div>
        `),
        ...res.datasets.map((d) => skItem({ url: `https://huggingface.co/datasets/${d.id}` })`
          <div>
            <div><strong>${d.id}</strong></div>
            <div><span style="font-size: 0.9em; opacity: 70%">dataset</span></div>
          </div>
        `),
      ];
    },
  },
  {
    alias: 'ci', name: 'caniuse',
    search: 'https://caniuse.com/?search=',
    compl: 'https://caniuse.com/process/query.php?search=',
    favicon: ddgIcon('caniuse.com'),
    cb: (r) => JSON.parse(r.text).featureIds.map((id) => skUrlItem(id, `https://caniuse.com/${id}`)),
  },
  {
    alias: 'ts', name: 'typescript',
    search: 'https://duckduckgo.com/?q=site%3Awww.typescriptlang.org+',
    compl: 'https://bgcdyoiyz5-dsn.algolia.net/1/indexes/typescriptlang?x-algolia-application-id=BGCDYOIYZ5&x-algolia-api-key=37ee06fa68db6aef451a490df6df7c60&query=',
    favicon: ddgIcon('www.typescriptlang.org'),
    cb: (r) => JSON.parse(r.text).hits.map((hit) => {
      const levels = Object.values(hit.hierarchy).filter(Boolean);
      return skUrlItem(levels[levels.length - 1] || '', hit.url);
    }),
  },
  // ---- Ported from b0o/surfingkeys-conf (missing engines) ----
  {
    alias: 'G', name: 'google-lucky',
    search: 'https://www.google.com/search?btnI=1&q=',
    compl: 'https://www.google.com/complete/search?client=chrome-omni&gs_ri=chrome-ext&oit=1&cp=1&pgcl=7&q=',
    favicon: ddgIcon('www.google.com'),
    cb: (r) => JSON.parse(r.text)[1],
  },
  {
    alias: 'at', name: 'alternativeto',
    search: 'https://alternativeto.net/browse/search/?q=',
    compl: 'https://www.algolia.com/api/1/search?x-algolia-application-id=HRCBJ9KX2A&x-algolia-api-key=465ab209a0d4f2d4f0f0c1a0c1e8e5d0&x-algolia-index-name=prod_altervisto&query=',
    favicon: ddgIcon('alternativeto.net'),
    cb: (r) => {
      const res = JSON.parse(r.text).hits || [];
      return res.map((s) => skUrlItem(`${s.Likes ? `[↑${s.Likes}] ` : ''}${s.Name}`, s.Url || `https://alternativeto.net/software/${s.UrlName}/`));
    },
  },
  {
    alias: 'au', name: 'AUR',
    search: 'https://aur.archlinux.org/packages/?O=0&SeB=nd&outdated=&SB=v&SO=d&PP=100&do_Search=Go&K=',
    compl: 'https://aur.archlinux.org/rpc?v=5&type=suggest&arg=',
    favicon: ddgIcon('aur.archlinux.org'),
    cb: (r) => JSON.parse(r.text).map((s) => skUrlItem(s, `https://aur.archlinux.org/packages/${s}`)),
  },
  {
    alias: 'az', name: 'amazon',
    search: 'https://smile.amazon.com/s/?field-keywords=',
    compl: 'https://completion.amazon.com/search/complete?method=completion&mkt=1&search-alias=aps&q=',
    favicon: ddgIcon('smile.amazon.com'),
    cb: (r) => JSON.parse(r.text)[1] || [],
  },
  {
    alias: 'cl', name: 'craigslist',
    search: 'https://www.craigslist.org/search/sss?query=',
    compl: 'https://www.craigslist.org/suggest?v=12&type=search&cat=sss&area=1&term=',
    favicon: ddgIcon('www.craigslist.org'),
    cb: (r) => JSON.parse(r.text),
  },
  {
    alias: 'co', name: 'crunchbase-orgs',
    search: 'https://www.crunchbase.com/textsearch?q=',
    favicon: ddgIcon('www.crunchbase.com'),
  },
  {
    alias: 'cp', name: 'crunchbase-people',
    search: 'https://www.crunchbase.com/app/search/?q=',
    favicon: ddgIcon('www.crunchbase.com'),
  },
  {
    alias: 'dd', name: 'duckduckgo',
    search: 'https://duckduckgo.com/?q=',
    compl: 'https://duckduckgo.com/ac/?q=',
    favicon: ddgIcon('duckduckgo.com'),
    cb: (r) => JSON.parse(r.text).map((x) => x.phrase),
  },
  {
    alias: 'de', name: 'define',
    search: 'http://onelook.com/?w=',
    compl: 'https://api.datamuse.com/words?md=d&sp=%s*',
    favicon: ddgIcon('onelook.com'),
    cb: (r) => JSON.parse(r.text).map((w) => skUrlItem(w.word, `http://onelook.com/?w=${encodeURIComponent(w.word)}`)),
  },
  {
    alias: 'dm', name: 'duckduckgo-maps',
    search: 'https://duckduckgo.com/?ia=maps&iax=maps&iaxm=places&q=',
    compl: 'https://duckduckgo.com/ac/?ia=maps&iax=maps&iaxm=places&q=',
    favicon: ddgIcon('duckduckgo.com'),
    cb: (r) => JSON.parse(r.text).map((x) => x.phrase),
  },
  {
    alias: 'dn', name: 'duckduckgo-news',
    search: 'https://duckduckgo.com/?iar=news&ia=news&q=',
    compl: 'https://duckduckgo.com/ac/?iar=news&ia=news&q=',
    favicon: ddgIcon('duckduckgo.com'),
    cb: (r) => JSON.parse(r.text).map((x) => x.phrase),
  },
  {
    alias: 'do', name: 'domainr',
    search: 'https://domainr.com/?q=',
    compl: 'https://5jmgqstc3m.execute-api.us-west-1.amazonaws.com/v1/domainr?q=',
    favicon: ddgIcon('domainr.com'),
    cb: (r) => JSON.parse(r.text),
  },
  {
    alias: 'eb', name: 'ebay',
    search: 'https://www.ebay.com/sch/i.html?_nkw=',
    compl: 'https://autosug.ebay.com/autosug?callback=0&sId=0&kwd=',
    favicon: ddgIcon('www.ebay.com'),
    cb: (r) => JSON.parse(r.text).res.sug.map((s) => s[0]),
  },
  {
    alias: 'fa', name: 'firefox-addons',
    search: 'https://addons.mozilla.org/firefox/search/?q=',
    compl: 'https://addons.mozilla.org/api/v4/addons/autocomplete/?q=',
    favicon: ddgIcon('addons.mozilla.org'),
    cb: (r) => JSON.parse(r.text).results.map((s) => skUrlItem(s.name, s.url)),
  },
  {
    alias: 'fe', name: 'firefox-extensions',
    search: 'https://addons.mozilla.org/firefox/search/?q=',
    compl: 'https://addons.mozilla.org/api/v4/addons/autocomplete/?type=extension&q=',
    favicon: ddgIcon('addons.mozilla.org'),
    cb: (r) => JSON.parse(r.text).results.map((s) => skUrlItem(s.name, s.url)),
  },
  {
    alias: 'ft', name: 'firefox-themes',
    search: 'https://addons.mozilla.org/firefox/search/?q=',
    compl: 'https://addons.mozilla.org/api/v4/addons/autocomplete/?type=statictheme&q=',
    favicon: ddgIcon('addons.mozilla.org'),
    cb: (r) => JSON.parse(r.text).results.map((s) => skUrlItem(s.name, s.url)),
  },
  {
    alias: 'gI', name: 'google-reverse-image',
    search: 'https://www.google.com/searchbyimage?image_url=',
    favicon: ddgIcon('www.google.com'),
  },
  {
    alias: 'gd', name: 'godoc',
    search: 'https://godoc.org/?q=',
    compl: 'https://api.godoc.org/search?q=',
    favicon: ddgIcon('godoc.org'),
    cb: (r) => JSON.parse(r.text).results.map((s) => skUrlItem(s.package, `https://godoc.org/${s.package}`)),
  },
  {
    alias: 'ha', name: 'hackage',
    search: 'https://hackage.haskell.org/packages/search?terms=',
    compl: 'https://hackage.haskell.org/packages/search.json?terms=',
    favicon: ddgIcon('hackage.haskell.org'),
    cb: (r) => JSON.parse(r.text).map((s) => skUrlItem(s.packageName, `https://hackage.haskell.org/package/${s.packageName}`)),
  },
  {
    alias: 'hd', name: 'hexdocs',
    search: 'https://hex.pm/packages?sort=downloads&search=',
    compl: 'https://hex.pm/api/packages?sort=downloads&hd&search=',
    favicon: ddgIcon('hex.pm'),
    cb: (r) => JSON.parse(r.text).map((s) => skUrlItem(s.name, `https://hexdocs.pm/${s.name}`)),
  },
  {
    alias: 'ho', name: 'hoogle',
    search: 'https://www.haskell.org/hoogle/?hoogle=',
    compl: 'https://www.haskell.org/hoogle/?mode=json&hoogle=',
    favicon: ddgIcon('www.haskell.org'),
    cb: (r) => JSON.parse(r.text).map((s) => skUrlItem(s.display, s.url)),
  },
  {
    alias: 'hw', name: 'haskellwiki',
    search: 'https://wiki.haskell.org/index.php?go=go&search=',
    compl: 'https://wiki.haskell.org/api.php?action=opensearch&format=json&formatversion=2&namespace=0&limit=10&suggest=true&search=',
    favicon: ddgIcon('wiki.haskell.org'),
    cb: (r) => JSON.parse(r.text)[1],
  },
  {
    alias: 'hx', name: 'hex',
    search: 'https://hex.pm/packages?sort=downloads&search=',
    compl: 'https://hex.pm/api/packages?sort=downloads&hx&search=',
    favicon: ddgIcon('hex.pm'),
    cb: (r) => JSON.parse(r.text).map((s) => skUrlItem(s.name, `https://hex.pm/packages/${s.name}`)),
  },
  {
    alias: 'ka', name: 'kagi',
    search: 'https://kagi.com/search?q=',
    compl: 'https://kagi.com/autosuggest?q=',
    favicon: ddgIcon('kagi.com'),
    cb: (r) => JSON.parse(r.text).map((x) => skUrlItem(x.t, x.goto || `https://kagi.com/search?q=${encodeURIComponent(x.t)}`)),
  },
  {
    alias: 'ow', name: 'owasp',
    search: 'https://www.owasp.org/index.php?go=go&search=',
    compl: 'https://www.owasp.org/api.php?action=opensearch&format=json&formatversion=2&namespace=0&limit=10&suggest=true&search=',
    favicon: ddgIcon('www.owasp.org'),
    cb: (r) => JSON.parse(r.text)[1],
  },
  {
    alias: 'th', name: 'thesaurus',
    search: 'https://www.onelook.com/thesaurus/?s=',
    compl: 'https://api.datamuse.com/words?md=d&ml=%s',
    favicon: ddgIcon('www.onelook.com'),
    cb: (r) => JSON.parse(r.text).map((w) => skUrlItem(w.word, `https://www.onelook.com/thesaurus/?s=${encodeURIComponent(w.word)}`)),
  },
  {
    alias: 'tw', name: 'twitter',
    search: 'https://twitter.com/search?q=',
    favicon: ddgIcon('twitter.com'),
  },
  {
    alias: 'vw', name: 'vimwiki',
    search: 'https://vim.fandom.com/wiki/Special:Search?query=',
    compl: 'https://vim.fandom.com/api.php?action=opensearch&format=json&formatversion=2&namespace=0&limit=10&suggest=true&search=',
    favicon: ddgIcon('vim.fandom.com'),
    cb: (r) => JSON.parse(r.text)[1],
  },
  {
    alias: 'wa', name: 'wolframalpha',
    search: 'http://www.wolframalpha.com/input/?i=',
    favicon: ddgIcon('www.wolframalpha.com'),
  },
  {
    alias: 'ws', name: 'wikipedia-simple',
    search: 'https://simple.wikipedia.org/w/index.php?search=',
    compl: 'https://simple.wikipedia.org/w/api.php?action=query&format=json&generator=prefixsearch&prop=info|pageprops%7Cpageimages%7Cdescription&redirects=&ppprop=displaytitle&piprop=thumbnail&pithumbsize=100&pilimit=6&inprop=url&gpssearch=',
    favicon: ddgIcon('simple.wikipedia.org'),
    cb: (r) => Object.values(JSON.parse(r.text).query.pages).map((p) => p.title),
  },
  {
    alias: 'yp', name: 'yelp',
    search: 'https://www.yelp.com/search?find_desc=',
    compl: 'https://www.yelp.com/search_suggest/v2/prefetch?prefix=',
    favicon: ddgIcon('www.yelp.com'),
    cb: (r) => {
      const res = JSON.parse(r.text).response;
      const words = [];
      (res || []).forEach((rr) => (rr.suggestions || []).forEach((s) => {
        const w = s.query;
        if (words.indexOf(w) === -1) words.push(w);
      }));
      return words;
    },
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

// ========== Omnibar-only extras (no normal-mode impact) ==========
// cmap bindings apply ONLY inside the omnibar overlay — normal-mode keys untouched.
api.cmap('<Alt-j>', '<Ctrl-n>'); // next suggestion
api.cmap('<Alt-k>', '<Ctrl-p>'); // previous suggestion
api.cmap('<Alt-l>', '<Ctrl-.>'); // complete with next tab URL
api.cmap('<Alt-h>', '<Ctrl-,>'); // complete with previous tab URL

// Suggestion fetch settings — affect only the omnibar overlay, not the native bar.
settings.omnibarSuggestionTimeout = 500;
settings.richHintsForKeystroke = 1;

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

// ========== Site-Specific Mappings (from b0o/surfingkeys-conf, leader <Space>) ==========
// <Space> is unbound in SurfingKeys defaults; each mapping is domain-scoped via opts.domain.

// GitHub
const ghRepoPath = () => {
  const parts = window.location.pathname.split('/').filter(Boolean);
  return parts.length >= 2 ? parts.slice(0, 2).join('/') : null;
};
api.mapkey('<Space>I', 'Open repository Issues page', () => {
  const r = ghRepoPath();
  if (r) window.location.assign(`https://github.com/${r}/issues`);
}, { domain: /github\.com/i });
api.mapkey('<Space>P', 'Open repository Pull Requests page', () => {
  const r = ghRepoPath();
  if (r) window.location.assign(`https://github.com/${r}/pulls`);
}, { domain: /github\.com/i });
api.mapkey('<Space>C', 'Open repository Commits page', () => {
  const r = ghRepoPath();
  if (r) window.location.assign(`https://github.com/${r}/commits`);
}, { domain: /github\.com/i });
api.mapkey('<Space>A', 'Open repository Actions page', () => {
  const r = ghRepoPath();
  if (r) window.location.assign(`https://github.com/${r}/actions`);
}, { domain: /github\.com/i });
api.mapkey('<Space>R', 'Open Repository page', () => {
  const r = ghRepoPath();
  if (r) window.location.assign(`https://github.com/${r}`);
}, { domain: /github\.com/i });
api.mapkey('<Space>N', 'Open notifications page', () => {
  window.location.assign('https://github.com/notifications');
}, { domain: /github\.com/i });
api.mapkey('<Space>yy', 'Copy project path', () => {
  const r = ghRepoPath();
  if (r) api.Clipboard.write(r);
}, { domain: /github\.com/i });
api.mapkey('<Space>Y', 'Copy project path with domain', () => {
  const r = ghRepoPath();
  if (r) api.Clipboard.write(`github.com/${r}`);
}, { domain: /github\.com/i });
api.mapkey('<Space>D', 'Open in github.dev', () => {
  const r = ghRepoPath();
  if (r) api.tabOpenLink(`https://github.dev/${r}`);
}, { domain: /github\.com/i });
api.mapkey('<Space>s', 'Toggle star', () => {
  const btn = document.querySelector('button[aria-label^="Star this repository"], button[aria-label^="Unstar"]');
  if (btn) btn.click();
}, { domain: /github\.com/i });
api.mapkey('gu', 'Go up one path in URL', () => {
  const parts = window.location.pathname.split('/').filter(Boolean).slice(0, -1);
  window.location.assign('https://github.com/' + parts.join('/'));
}, { domain: /github\.com/i });

// YouTube
api.mapkey('Yt', 'Copy YouTube link at current time', () => {
  const t = (document.querySelector('.ytp-time-current')?.innerText || '0:00')
    .split(':').reverse().map(Number);
  const secs = t.reduce((acc, n, i) => acc + n * Math.pow(60, i), 0);
  const v = new URLSearchParams(window.location.search).get('v');
  if (v) api.Clipboard.write(`https://youtu.be/${v}?t=${secs}`);
}, { domain: /youtube\.com/i });
api.mapkey('F', 'Toggle YouTube fullscreen', () => {
  const btn = document.querySelector('#movie_player .ytp-fullscreen-button');
  if (btn) btn.click();
}, { domain: /youtube\.com/i });
api.mapkey('A', 'Open video', () => api.Hints.create("*[id='video-title']", api.Hints.dispatchMouseClick), { domain: /youtube\.com/i });

// Reddit
api.mapkey('<Space>x', 'Collapse comment', () => api.Hints.create('.expand', api.Hints.dispatchMouseClick), { domain: /reddit\.com/i });
api.mapkey('<Space>s', 'Upvote', () => api.Hints.create('.arrow.up', api.Hints.dispatchMouseClick), { domain: /reddit\.com/i });
api.mapkey('<Space>a', 'View post', () => api.Hints.create('.title', api.Hints.dispatchMouseClick), { domain: /reddit\.com/i });
api.mapkey('<Space>c', 'View comments', () => api.Hints.create('.comments', api.Hints.dispatchMouseClick), { domain: /reddit\.com/i });

// Hacker News
api.mapkey('<Space>x', 'Collapse comment', () => api.Hints.create('a.togg', api.Hints.dispatchMouseClick), { domain: /news\.ycombinator\.com/i });
api.mapkey('<Space>s', 'Upvote', () => api.Hints.create(".votearrow[title='upvote']", api.Hints.dispatchMouseClick), { domain: /news\.ycombinator\.com/i });
api.mapkey('<Space>a', 'View post', () => api.Hints.create('.titleline>a', api.Hints.dispatchMouseClick), { domain: /news\.ycombinator\.com/i });
api.mapkey('<Space>c', 'View comments', () => api.Hints.create(".subline>a[href^='item']", api.Hints.dispatchMouseClick), { domain: /news\.ycombinator\.com/i });
api.mapkey('<Space>e', 'View external link', () => api.Hints.create('a[rel=nofollow]', api.Hints.dispatchMouseClick), { domain: /news\.ycombinator\.com/i });

// Stack Overflow
api.mapkey('<Space>a', 'View question', () => api.Hints.create('a.s-link', api.Hints.dispatchMouseClick), { domain: /stackoverflow\.com/i });

// AUR
api.mapkey('<Space>a', 'View package', () => api.Hints.create('a[href^="/packages/"]', api.Hints.dispatchMouseClick), { domain: /aur\.archlinux\.org/i });

// ========== Hint Utilities (from b0o/surfingkeys-conf) ==========
api.mapkey('yA', 'Copy link as Markdown', () =>
  api.Hints.create('a[href]', (a) => api.Clipboard.write(`[${a.innerText}](${a.href})`))
);
api.mapkey('yI', 'Copy image URL', () =>
  api.Hints.create('img', (i) => api.Clipboard.write(i.src))
);
api.mapkey('gI', 'View image in new tab', () =>
  api.Hints.create('img', (i) => api.tabOpenLink(i.src))
);

// ================= Ported from b0o/surfingkeys-conf =================
// Global utilities (compact port of actions.js/util.js — only what the
// ported mappings use). Prefixed p* to avoid clashes with the config above.

const pOpenLink = (url, { newTab = false, active = true } = {}) => {
  if (newTab) {
    api.RUNTIME('openLink', { tab: { tabbed: true, active }, url });
    return;
  }
  window.location.assign(url);
};
const pHints = (selector, action = api.Hints.dispatchMouseClick) =>
  new Promise((resolve) => {
    api.Hints.create(selector, (...args) => {
      resolve(...args);
      if (typeof action === 'function') action(...args);
    });
  });
const pInView = (e) => {
  const r = e.getBoundingClientRect();
  return e.offsetHeight > 0 && e.offsetWidth > 0 && !e.getAttribute('disabled') &&
    r.height > 0 && r.width > 0 && r.bottom >= 0 && r.right >= 0 &&
    r.top <= (window.innerHeight || document.documentElement.clientHeight) &&
    r.left <= (window.innerWidth || document.documentElement.clientWidth);
};
const pHintsFiltered = (filter, selector = 'a[href]', action = api.Hints.dispatchMouseClick) =>
  new Promise((resolve) => {
    const els = [...document.querySelectorAll(selector)].filter(filter);
    api.Hints.create(els, (...args) => {
      resolve(...args);
      if (typeof action === 'function') action(...args);
    });
  });
const pUntil = (check, test = (a) => a, maxAttempts = 50, interval = 50) =>
  new Promise((resolve, reject) => {
    const f = (attempts = 0) => {
      const res = check();
      if (!test(res)) {
        if (attempts > maxAttempts) reject(new Error('until: timeout'));
        else setTimeout(() => f(attempts + 1), interval);
        return;
      }
      resolve(res);
    };
    f();
  });
const pURLPath = ({ count = 0, domain = false } = {}) => {
  let path = window.location.pathname.slice(1);
  if (count) path = path.split('/').slice(0, count).join('/');
  if (domain) path = `${window.location.hostname}/${path}`;
  return path;
};
const pScrollToHash = () => {
  const h = document.location.hash.replace('#', '');
  const e = document.getElementById(h) || document.querySelector(`[name="${h}"]`);
  if (e) e.scrollIntoView({ behavior: 'smooth' });
};
const pOpenAnchor = ({ newTab = false, active = true, prop = 'href' } = {}) =>
  (a) => pOpenLink(a[prop], { newTab, active });

// --- Site actions ---
const pFakeSpot = () =>
  pOpenLink(`https://fakespot.com/analyze?ra=true&url=${window.location.href}`, { newTab: true, active: false });

const pAzViewProduct = () => {
  const reHost = /^([-\w]+[.])*amazon.\w+$/;
  const rePath = /^(?:.*\/)*(?:dp|gp\/product)(?:\/(\w{10})).*/;
  const elements = {};
  document.querySelectorAll('a[href]').forEach((a) => {
    const u = new URL(a.href);
    if (u.hash.length === 0 && reHost.test(u.hostname)) {
      const m = rePath.exec(u.pathname);
      if (m === null || m.length !== 2 || !pInView(a)) return;
      const asin = m[1];
      if (elements[asin] !== undefined) {
        if (!(elements[asin].text.trim().length === 0 && a.text.trim().length > 0)) return;
      }
      elements[asin] = a;
    }
  });
  api.Hints.create(Object.values(elements), api.Hints.dispatchMouseClick);
};

const pGoogleLoc = () => {
  const u = new URL(window.location.href);
  const q = u.searchParams.get('q');
  const p = u.pathname.split('/');
  const res = { type: 'unknown', url: u, query: q };
  if (u.hostname === 'www.google.com') {
    if (p.length <= 1) res.type = 'home';
    else if (p[1] === 'search') {
      switch (u.searchParams.get('tbm')) {
      case 'vid': res.type = 'videos'; break;
      case 'isch': res.type = 'images'; break;
      case 'nws': res.type = 'news'; break;
      default: res.type = 'web';
      }
    } else if (p[1] === 'maps') {
      res.type = 'maps';
      if (p[2] === 'search' && p[3] !== undefined) res.query = p[3];
      else if (p[2] !== undefined) res.query = p[2];
    }
  }
  return res;
};
const pGoDdg = () => {
  const g = pGoogleLoc();
  const ddg = new URL('https://duckduckgo.com');
  if (g.query) ddg.searchParams.set('q', g.query);
  switch (g.type) {
  case 'videos': ddg.searchParams.set('ia', 'videos'); ddg.searchParams.set('iax', 'videos'); break;
  case 'images': ddg.searchParams.set('ia', 'images'); ddg.searchParams.set('iax', 'images'); break;
  case 'news': ddg.searchParams.set('ia', 'news'); ddg.searchParams.set('iar', 'news'); break;
  case 'maps': ddg.searchParams.set('iaxm', 'maps'); break;
  default: ddg.searchParams.set('ia', 'web');
  }
  pOpenLink(ddg.href);
};
const pDgGoog = () => {
  let u;
  try { u = new URL(window.location.href); } catch (e) { return; }
  const q = u.searchParams.get('q');
  if (!q) return;
  const goog = new URL('https://google.com/search');
  goog.searchParams.set('q', q);
  const iax = u.searchParams.get('iax');
  const iaxm = u.searchParams.get('iaxm');
  const iar = u.searchParams.get('iar');
  if (iax === 'images') goog.searchParams.set('tbm', 'isch');
  else if (iax === 'videos') goog.searchParams.set('tbm', 'vid');
  else if (iar === 'news') goog.searchParams.set('tbm', 'nws');
  else if (iaxm === 'maps') goog.pathname = '/maps';
  pOpenLink(goog.href);
};
const pDgSiteSearch = (site) => {
  let u;
  try { u = new URL(window.location.href); } catch (e) { return; }
  const siteParam = `site:${site}`;
  const q = u.searchParams.get('q');
  if (!q) return;
  const i = q.indexOf(siteParam);
  if (i !== -1) u.searchParams.set('q', q.replace(siteParam, ''));
  else u.searchParams.set('q', `${q} ${siteParam}`);
  pOpenLink(u.href);
};

const pGhParseRepo = (url = window.location.href) => {
  let u;
  try { u = url instanceof URL ? url : new URL(url); } catch (e) { u = new URL(`https://github.com/${url}`); }
  const [user, repo, ...rest] = u.pathname.split('/').filter((s) => s !== '');
  const isRoot = rest.length === 0;
  if (['github.com', 'gist.github.com', 'raw.githubusercontent.com'].includes(u.hostname) &&
      user && repo && (isRoot || true) && /^([a-zA-Z0-9]+-?)+$/.test(user || '')) {
    return { user, repo, repoBase: `${user}/${repo}`, repoRoot: isRoot };
  }
  return null;
};
const pGhOpenPage = (path) => pOpenLink(`https://github.com/${path}`);
const pGhOpenRepoPage = (repoPath) => {
  const repo = pGhParseRepo();
  if (repo) pGhOpenPage(`${repo.repoBase}${repoPath}`);
};
const pGhOpenRepoOwner = () => {
  const repo = pGhParseRepo();
  if (repo) pGhOpenPage(repo.owner || repo.user);
};
const pGhOpenProfile = () => {
  const meta = document.querySelector("meta[name='user-login']");
  if (meta) pGhOpenPage(meta.content);
};
const pGhOpenRepo = () => pHintsFiltered((a) => pGhParseRepo(a.href));
const pGhOpenUser = () => pHintsFiltered((a) => {
  const u = new URL(a.href);
  const [user, ...rest] = u.pathname.split('/').filter(Boolean);
  return u.origin === window.location.origin && user && rest.length === 0 && /^([a-zA-Z0-9]+-?)+$/.test(user);
});
const pGhOpenFile = () => pHintsFiltered((a) => {
  const parts = new URL(a.href).pathname.split('/').filter(Boolean);
  return parts.length >= 4 && (parts[2] === 'blob' || parts[2] === 'tree');
});
const pGhOpenCommit = () => pHintsFiltered((a) => {
  const parts = new URL(a.href).pathname.split('/').filter(Boolean);
  return parts.length >= 3 && parts[2] === 'commit';
});
const pGhOpenIssue = () => pHintsFiltered((a) => {
  const parts = new URL(a.href).pathname.split('/').filter(Boolean);
  return parts.length >= 3 && parts[2] === 'issues';
});
const pGhOpenPull = () => pHintsFiltered((a) => {
  const parts = new URL(a.href).pathname.split('/').filter(Boolean);
  return parts.length >= 3 && /^pulls?$/.test(parts[2]);
});
const pGhOpenSourceFile = () => {
  const p = window.location.pathname.split('/');
  pGhOpenPage([...p.slice(1, 3), 'tree', ...p.slice(3)].join('/'));
};
const pGhOpenPagesRepo = () => {
  const user = window.location.hostname.split('.')[0];
  const repo = window.location.pathname.split('/')[1] || '';
  pGhOpenPage(`${user}/${repo}`);
};
const pGhRaw = () => {
  const p = window.location.pathname.split('/').filter(Boolean);
  if (p.length >= 4 && (p[2] === 'blob' || p[2] === 'tree')) {
    p[2] = p[2] === 'blob' ? 'raw' : 'tree';
    pOpenLink(`https://raw.githubusercontent.com/${p.join('/')}`);
  }
};
const pGhLangStats = () => {
  const g = document.querySelector('.repository-lang-stats-graph');
  if (g) g.click();
};
const pGhSourceGraph = () => {
  const parts = window.location.pathname.split('/').filter(Boolean);
  const base = parts.slice(0, 2).join('/');
  pOpenLink(`https://sourcegraph.com/github.com/${base}`, { newTab: true });
};

const pGlStar = () => {
  const repo = window.location.pathname.slice(1).split('/').slice(0, 2).join('/');
  const btn = document.querySelector('.btn.star-btn > span');
  if (!btn) return;
  btn.click();
  const action = `${btn.textContent.toLowerCase()}red`;
  api.Front.showBanner(`${action === 'starred' ? '★' : '☆'} Repository ${repo} ${action}`);
};
const pViewGodoc = () =>
  pOpenLink(`https://godoc.org/${pURLPath({ count: 2, domain: true })}`, { newTab: true });

const pTwOpenUser = () =>
  pHints([].concat(
    [...document.querySelectorAll("a[role='link'] img[src^='https://pbs.twimg.com/profile_images']")]
      .map((e) => e.closest('a')),
    [...document.querySelectorAll("a[role='link']")]
      .filter((e) => e.text.match(/^@/)),
  ));

const pReCollapseNext = (sel) => {
  const vis = Array.from(document.querySelectorAll(sel)).filter((e) => pInView(e));
  if (vis.length > 0) vis[0].click();
};
const pHnGoParent = () => {
  const par = document.querySelector(".navs>a[href^='item']");
  if (par) pOpenLink(par.href);
};
const pHnGoPage = (dist = 1) => {
  let u;
  try { u = new URL(window.location.href); } catch (e) { return; }
  let page = u.searchParams.get('p');
  if (page === null || page === '') page = '1';
  const cur = parseInt(page, 10);
  if (Number.isNaN(cur)) return;
  const dest = cur + dist;
  if (dest < 1) return;
  u.searchParams.set('p', dest);
  pOpenLink(u.href);
};
const pHnOpenLinkAndComments = (e) => {
  const linkUrl = e.querySelector('.titleline>a');
  const commentsUrl = e.nextElementSibling && e.nextElementSibling.querySelector("a[href^='item']:not(.titlelink)");
  if (commentsUrl) pOpenLink(commentsUrl.href, { newTab: true });
  if (linkUrl) pOpenLink(linkUrl.href, { newTab: true });
};

const pWpToggleSimple = () => {
  const u = new URL(window.location.href);
  u.hostname = u.hostname.split('.').map((s, i) => (i === 0 ? (s === 'simple' ? '' : 'simple') : s))
    .filter((s) => s !== '').join('.');
  pOpenLink(u.href);
};
const pWpViewWikiRank = () => {
  const h = document.location.hostname.split('.');
  const lang = h.length > 2 && h[0] !== 'www' ? h[0] : 'en';
  const p = document.location.pathname.split('/');
  if (p.length < 3 || p[1] !== 'wiki') return;
  pOpenLink(`https://wikirank.net/${lang}/${p.slice(2).join('/')}`, { newTab: true });
};
const pWpMarkdownSummary = () => {
  const clone = document.querySelector('#mw-content-text p:not([class]):not([id])');
  if (!clone) return;
  const node = clone.cloneNode(true);
  [...node.querySelectorAll('sup')].forEach((e) => e.remove());
  [...node.querySelectorAll('b')].forEach((e) => { e.innerText = `**${e.innerText}**`; });
  [...node.querySelectorAll('i')].forEach((e) => { e.innerText = `_${e.innerText}_`; });
  api.Clipboard.write(`> ${node.innerText.trim()}\n\n— [${document.title}](${window.location.href})`);
};

const pPhOpenExternal = () =>
  api.Hints.create("ul[class^='postsList_'] > li > div[class^='item_']", (p) => {
    const a = p.querySelector("div[class^='meta_'] div[class^='actions_'] div[class^='minorActions_'] a:nth-child(1)");
    if (a) pOpenLink(a.href, { newTab: true });
  });

const pNtAdjustTemp = (dir) => {
  const btn = document.querySelector(
    `button[data-test='thermozilla-controller-controls-${dir > 0 ? 'in' : 'de'}crement-button']`);
  if (btn) btn.click();
};
const pNtSetMode = (mode) => {
  const click = (sel) => { const b = document.querySelector(sel); if (b) b.click(); };
  const openPopover = async () => {
    const existing = document.querySelector("div[data-test='thermozilla-mode-popover']");
    if (existing) return existing;
    click("button[data-test='thermozilla-mode-button']");
    return pUntil(() => document.querySelector("div[data-test='thermozilla-mode-popover']"));
  };
  openPopover().then((popover) => {
    const b = popover.querySelector(`button[data-test='thermozilla-mode-switcher-${mode}-button']`);
    if (b) b.click();
  });
};
const pNtSetFan = (desired) => {
  const click = (sel) => { const b = document.querySelector(sel); if (b) b.click(); };
  const fanRunning = () => document.querySelector("div[data-test='thermozilla-aag-fan-listcell-title']");
  const openPopover = async () => {
    const existing = document.querySelector("div[data-test='thermozilla-fan-timer-popover']");
    if (existing) return existing;
    click("button[data-test='thermozilla-fan-button']");
    return pUntil(() => document.querySelector("div[data-test='thermozilla-fan-timer-popover']"));
  };
  const stop = async () => {
    const popover = await openPopover();
    const b = popover.querySelector("div[data-test='thermozilla-fan-timer-stop-button']");
    if (b) b.click();
  };
  const start = async () => {
    const popover = await openPopover();
    const listbox = popover.querySelector("div[role='listbox']");
    if (listbox) api.Hints.dispatchMouseClick(listbox.querySelector("div[role='option']:last-child"));
    const b = popover.querySelector("div[data-test='thermozilla-fan-timer-start-button']");
    if (b) b.click();
  };
  if (fanRunning()) { stop(); }
  if (desired === 1) { start(); }
};

const pScrollEl = (el, dir) => {
  if (!el) return;
  const e = document.createEvent('MouseEvents');
  e.initEvent('mousedown', true, true);
  el.dispatchEvent(e);
  api.Normal.scroll(dir);
};
const pDvScrollSidebar = (dir) => pScrollEl(document.querySelector('._list'), dir);
const pDvScrollContent = (dir) => pScrollEl(document.querySelector('._content'), dir);
const pReScrollSidebar = (dir) => pScrollEl(document.getElementById('sidebar-content'), dir);
const pReScrollContent = (dir) => pScrollEl(document.body, dir);
const pReFocusSearch = () => {
  const el = document.getElementById('docsearch');
  if (!el) return;
  const e = document.createEvent('MouseEvents');
  e.initEvent('mousedown', true, true);
  el.dispatchEvent(e);
  e.initEvent('click', true, true);
  el.dispatchEvent(e);
};

const pIkToggleDetails = () => {
  const close = document.querySelector('.range-revamp-modal-header__close');
  if (close) { close.click(); return; }
  const btn = document.querySelector('.range-revamp-product-information-section__button button');
  if (!btn) return;
  btn.click();
  const expand = document.querySelector('.range-revamp-expander__btn');
  if (expand) expand.click();
  else pUntil(() => document.querySelector('.range-revamp-expander__btn')).then((e) => e.click());
};
const pIkToggleReviews = () => {
  const btn = document.querySelector('.ugc-rr-pip-fe-modal-header__close') ||
    document.querySelector('.range-revamp-chunky-header__reviews');
  if (btn) btn.click();
};

const pYtTimestampLink = () => {
  const [ss, mm, hh = 0] = (document.querySelector('#ytd-player .ytp-time-current')
    ?.innerText?.split(':')?.reverse()?.map(Number)) ?? [0, 0, 0];
  const secs = (hh * 60 * 60) + (mm * 60) + ss;
  const v = new URLSearchParams(window.location.search).get('v');
  return v ? `https://youtu.be/${v}?t=${secs}` : null;
};

// ---- Global mappings (ported) ----
api.mapkey('zf', 'Open link URL in vim editor', () =>
  pHints('a[href]', (a) => api.Front.showEditor(a.href, (url) => pOpenLink(url), 'url'))
);
api.mapkey('gh', 'Scroll to element targeted by URL hash', () => pScrollToHash());
api.mapkey('gi', 'Edit current URL with vim editor', () =>
  api.Front.showEditor(window.location.href, (url) => pOpenLink(url), 'url')
);
api.mapkey('yp', 'Copy URL path of current page', () => api.Clipboard.write(window.location.href));
api.mapkey('yO', 'Copy page URL/Title as Org-mode link', () =>
  api.Clipboard.write(`[[${window.location.href}][${document.title}]]`)
);
api.mapkey('yT', 'Duplicate current tab (non-active new tab)', () =>
  pOpenLink(window.location.href, { newTab: true, active: false })
);
api.mapkey(';se', 'Edit Settings', () => api.tabOpenLink(chrome.extension.getURL('/pages/options.html')));
const pDossier = (params) =>
  `http://centralops.net/co/DomainDossier.aspx?${params}&addr=${window.location.hostname}`;
api.mapkey('=W', 'Lookup whois information for domain', () => pOpenLink(pDossier('dom_whois=true'), { newTab: true }));
api.mapkey('=d', 'Lookup dns information for domain', () => pOpenLink(pDossier('dom_dns=true'), { newTab: true }));
api.mapkey('=D', 'Lookup all information for domain', () =>
  pOpenLink(pDossier('dom_whois=true&dom_dns=true&traceroute=true&net_whois=true&svc_scan=true'), { newTab: true }));
api.mapkey('=c', "Show Google's cached version of page", () =>
  pOpenLink(`https://webcache.googleusercontent.com/search?q=cache:${window.location.href}`, { newTab: true }));
api.mapkey('=A', 'Show Alexa.com info for domain', () =>
  pOpenLink(`https://www.alexa.com/siteinfo/${window.location.hostname}`, { newTab: true }));
api.mapkey('=bw', 'Show BuiltWith report for page', () =>
  pOpenLink(`https://www.builtwith.com/?${window.location.href}`, { newTab: true }));
api.mapkey('=wa', 'Show Wappalyzer report for domain', () =>
  pOpenLink(`https://www.wappalyzer.com/lookup/${window.location.hostname}`, { newTab: true }));
api.mapkey('\\cgh', "Open clipboard string as GitHub path (e.g. 'torvalds/linux')", async () => {
  const clip = await navigator.clipboard.readText();
  const parts = clip.trim().replace(/^https?:\/\/github\.com\//, '').split('/').filter(Boolean);
  const url = 'https://github.com/' + parts.slice(0, 2).join('/');
  api.Front.showBanner(`Open ${url}`);
  pOpenLink(url, { newTab: true });
});

// ---- Site-specific (ported) ----

// Amazon
api.mapkey('<Space>fs', 'Fakespot', () => pFakeSpot(), { domain: /amazon\.(com|de|co\.uk|ca|fr|it|es|nl|com\.au|in|jp)\b/i });
api.mapkey('<Space>a', 'View product', () => pAzViewProduct(), { domain: /amazon\.(com|de|co\.uk|ca|fr|it|es|nl|com\.au|in|jp)\b/i });
api.mapkey('<Space>c', 'Add to Cart', () => pHints('#add-to-cart-button'), { domain: /amazon\.(com|de|co\.uk|ca|fr|it|es|nl|com\.au|in|jp)\b/i });
api.mapkey('<Space>R', 'View Product Reviews', () => pHints('#customerReviews'), { domain: /amazon\.(com|de|co\.uk|ca|fr|it|es|nl|com\.au|in|jp)\b/i });
api.mapkey('<Space>Q', 'View Product Q&A', () => pHints('#Ask'), { domain: /amazon\.(com|de|co\.uk|ca|fr|it|es|nl|com\.au|in|jp)\b/i });
api.mapkey('<Space>A', 'Open Account page', () => pOpenLink('/gp/css/homepage.html'), { domain: /amazon\.(com|de|co\.uk|ca|fr|it|es|nl|com\.au|in|jp)\b/i });
api.mapkey('<Space>C', 'Open Cart page', () => pOpenLink('/gp/cart/view.html'), { domain: /amazon\.(com|de|co\.uk|ca|fr|it|es|nl|com\.au|in|jp)\b/i });
api.mapkey('<Space>O', 'Open Orders page', () => pOpenLink('/gp/css/order-history'), { domain: /amazon\.(com|de|co\.uk|ca|fr|it|es|nl|com\.au|in|jp)\b/i });

// Google
const pGoogleResultsSel = [
  'a h3', 'h3 a',
  "a[href^='/search']:not(.fl):not(#pnnext,#pnprev):not([role]):not(.hide-focus-ring)",
  'g-scrolling-carousel a', '.rc > div:nth-child(2) a', '.kno-rdesc a', '.kno-fv a',
  '.isv-r > a:first-child', '.dbsr > a:first-child', '.X5OiLe', '.WlydOe', '.fl',
].join(',');
api.mapkey('<Space>a', 'Open search result', () => pHints(pGoogleResultsSel), { domain: /www\.google\.com/i });
api.mapkey('<Space>A', 'Open search result (new tab)', () => pHints(pGoogleResultsSel, pOpenAnchor({ newTab: true, active: false })), { domain: /www\.google\.com/i });
api.mapkey('<Space>d', 'Open search in DuckDuckGo', () => pGoDdg(), { domain: /www\.google\.com/i });

// Algolia
api.mapkey('<Space>a', 'Open search result', () => pHints('.item-main h2>a:first-child'), { domain: /algolia\.com/i });

// DuckDuckGo
const pDdgSel = [
  'a[rel=noopener][target=_self]:not([data-testid=result-extras-url-link])',
  '.js-images-show-more', '.module--images__thumbnails__link', '.tile--img__sub',
].join(',');
api.mapkey('<Space>a', 'Open search result', () => pHints(pDdgSel), { domain: /duckduckgo\.com/i });
api.mapkey('<Space>A', 'Open search result (non-active new tab)', () => pHints(pDdgSel, pOpenAnchor({ newTab: true, active: false })), { domain: /duckduckgo\.com/i });
api.mapkey(']]', 'Show more results', () => {
  const b = document.querySelector('.result--more__btn');
  if (b) b.click();
}, { domain: /duckduckgo\.com/i });
api.mapkey('<Space>g', 'Open search in Google', () => pDgGoog(), { domain: /duckduckgo\.com/i });
api.mapkey('<Space>sgh', 'Search site:github.com', () => pDgSiteSearch('github.com'), { domain: /duckduckgo\.com/i });
api.mapkey('<Space>sre', 'Search site:reddit.com', () => pDgSiteSearch('reddit.com'), { domain: /duckduckgo\.com/i });

// Yelp
api.mapkey('<Space>fs', 'Fakespot', () => pFakeSpot(), { domain: /yelp\.com/i });

// YouTube (additions; A/F/Yt already defined above)
api.mapkey('C', 'Open channel', () => pHints("*[id='byline']"), { domain: /youtube\.com/i });
api.mapkey('gH', 'Goto homepage', () => pOpenLink('https://www.youtube.com/feed/subscriptions?flow=2'), { domain: /youtube\.com/i });
api.mapkey('Ym', 'Copy YouTube video markdown link for current time', () => {
  const link = pYtTimestampLink();
  if (link) api.Clipboard.write(`[${document.title}](${link})`);
}, { domain: /youtube\.com/i });

// Vimeo
api.mapkey('<Space>F', 'Toggle fullscreen', () => {
  const b = document.querySelector('.fullscreen-icon');
  if (b) b.click();
}, { domain: /vimeo\.com/i });

// GitHub (additions; the rest defined above)
api.mapkey('<Space>S', 'Open repository Settings page', () => pGhOpenRepoPage('/settings'), { domain: /github\.com/i });
api.mapkey('<Space>W', 'Open repository Wiki page', () => pGhOpenRepoPage('/wiki'), { domain: /github\.com/i });
api.mapkey('<Space>X', 'Open repository Security page', () => pGhOpenRepoPage('/security'), { domain: /github\.com/i });
api.mapkey('<Space>O', "Open repository Owner's profile page", () => pGhOpenRepoOwner(), { domain: /github\.com/i });
api.mapkey('<Space>M', "Open your profile page ('Me')", () => pGhOpenProfile(), { domain: /github\.com/i });
api.mapkey('<Space>a', 'View Repository', () => pGhOpenRepo(), { domain: /github\.com/i });
api.mapkey('<Space>u', 'View User', () => pGhOpenUser(), { domain: /github\.com/i });
api.mapkey('<Space>f', 'View File', () => pGhOpenFile(), { domain: /github\.com/i });
api.mapkey('<Space>c', 'View Commit', () => pGhOpenCommit(), { domain: /github\.com/i });
api.mapkey('<Space>i', 'View Issue', () => pGhOpenIssue(), { domain: /github\.com/i });
api.mapkey('<Space>p', 'View Pull Request', () => pGhOpenPull(), { domain: /github\.com/i });
api.mapkey('<Space>e', 'View external link', () => pHints("a[href^='http']:not([href*='github.com'])"), { domain: /github\.com/i });
api.mapkey('<Space>l', 'Toggle repo language stats', () => pGhLangStats(), { domain: /github\.com/i });
api.mapkey('<Space>G', 'View on SourceGraph', () => pGhSourceGraph(), { domain: /github\.com/i });
api.mapkey('<Space>r', 'View live raw version of file', () => pGhRaw(), { domain: /github\.com/i });
api.mapkey('<Space>yr', 'Copy raw link to file', () => {
  const p = window.location.pathname.split('/').filter(Boolean);
  if (p.length >= 4 && p[2] === 'blob') {
    p[2] = 'raw';
    api.Clipboard.write(`https://raw.githubusercontent.com/${p.join('/')}`);
  }
}, { domain: /github\.com/i });
api.mapkey('<Space>yf', 'Copy link to file', () => api.Clipboard.write(window.location.href), { domain: /github\.com/i });
api.mapkey('<Space>gcp', 'Open clipboard string as file path in repo', async () => {
  const clip = await navigator.clipboard.readText();
  const repo = pGhParseRepo();
  if (!repo) return;
  pOpenLink(`https://github.com/${repo.repoBase}/tree/master/${clip}`, { newTab: true });
}, { domain: /github\.com/i });

// raw.githubusercontent.com
api.mapkey('<Space>R', 'Open Repository page', () => pGhOpenRepoPage('/'), { domain: /raw\.githubusercontent\.com/i });
api.mapkey('<Space>F', 'Open Source File', () => pGhOpenSourceFile(), { domain: /raw\.githubusercontent\.com/i });

// github.io
api.mapkey('<Space>R', 'Open Repository page', () => pGhOpenPagesRepo(), { domain: /\.github\.io$/i });

// GitLab
api.mapkey('<Space>s', 'Toggle Star', () => pGlStar(), { domain: /gitlab\.com/i });
api.mapkey('<Space>y', 'Copy Project Path', () => api.Clipboard.write(pURLPath({ count: 2 })), { domain: /gitlab\.com/i });
api.mapkey('<Space>Y', 'Copy Project Path (including domain)', () => api.Clipboard.write(pURLPath({ count: 2, domain: true })), { domain: /gitlab\.com/i });
api.mapkey('<Space>D', 'View GoDoc for Project', () => pViewGodoc(), { domain: /gitlab\.com/i });

// Twitter
api.mapkey('<Space>f', 'Follow user', () => pHints("div[role='button'][data-testid$='follow']"), { domain: /twitter\.com/i });
api.mapkey('<Space>s', 'Like tweet', () => pHints("div[role='button'][data-testid$='like']"), { domain: /twitter\.com/i });
api.mapkey('<Space>R', 'Retweet', () => pHints("div[role='button'][data-testid$='retweet']"), { domain: /twitter\.com/i });
api.mapkey('<Space>c', 'Comment/Reply', () => pHints("div[role='button'][data-testid='reply']"), { domain: /twitter\.com/i });
api.mapkey('<Space>T', 'New tweet', () => {
  const b = document.querySelector("a[role='button'][data-testid='SideNav_NewTweet_Button']");
  if (b) b.click();
}, { domain: /twitter\.com/i });
api.mapkey('<Space>u', 'Goto user', () => pTwOpenUser(), { domain: /twitter\.com/i });
api.mapkey('<Space>t', 'Goto tweet', () =>
  pHints("article, article div[data-focusable='true'][role='link'][tabindex='0']"), { domain: /twitter\.com/i });

// Reddit (additions)
api.mapkey('<Space>X', 'Collapse next comment', () => pReCollapseNext('.noncollapsed.comment .expand'), { domain: /reddit\.com/i });
api.mapkey('<Space>S', 'Downvote', () => pHints('.arrow.down'), { domain: /reddit\.com/i });
api.mapkey('<Space>e', 'Expand expando', () => pHints('.expando-button'), { domain: /reddit\.com/i });
api.mapkey('<Space>A', 'View post (link) (non-active new tab)', () => pHints('.title', pOpenAnchor({ newTab: true, active: false })), { domain: /reddit\.com/i });
api.mapkey('<Space>C', 'View post (comments) (non-active new tab)', () => pHints('.comments', pOpenAnchor({ newTab: true, active: false })), { domain: /reddit\.com/i });

// Hacker News (additions)
api.mapkey('<Space>X', 'Collapse next comment', () => pReCollapseNext("a.togg"), { domain: /news\.ycombinator\.com/i });
api.mapkey('<Space>S', 'Downvote', () => pHints(".votearrow[title='downvote']"), { domain: /news\.ycombinator\.com/i });
api.mapkey('<Space>A', 'View post (link and comments)', () => pHints('.athing', pHnOpenLinkAndComments), { domain: /news\.ycombinator\.com/i });
api.mapkey('<Space>C', 'View post (comments) (non-active new tab)', () => pHints(".subline>a[href^='item']", pOpenAnchor({ newTab: true, active: false })), { domain: /news\.ycombinator\.com/i });
api.mapkey('gp', 'Go to parent', () => pHnGoParent(), { domain: /news\.ycombinator\.com/i });
api.mapkey(']]', 'Next page', () => pHnGoPage(1), { domain: /news\.ycombinator\.com/i });
api.mapkey('[[', 'Prev page', () => pHnGoPage(-1), { domain: /news\.ycombinator\.com/i });

// Product Hunt
api.mapkey('<Space>a', 'View product (external)', () => pPhOpenExternal(), { domain: /producthunt\.com/i });
api.mapkey('<Space>v', 'View product', () => pHints("ul[class^='postsList_'] > li > div[class^='item_'] > a"), { domain: /producthunt\.com/i });
api.mapkey('<Space>s', 'Upvote product', () => pHints("button[data-test='vote-button']"), { domain: /producthunt\.com/i });

// Behance
api.mapkey('<Space>s', 'Appreciate project', () => pHints('.appreciation-button'), { domain: /behance\.net/i });
api.mapkey('<Space>b', 'Add project to collection', () => {
  const b = document.querySelector('.qa-action-collection');
  if (b) b.click();
}, { domain: /behance\.net/i });
api.mapkey('<Space>a', 'View project', () => pHints('.rf-project-cover__title'), { domain: /behance\.net/i });
api.mapkey('<Space>A', 'View project (non-active new tab)', () => pHints('.rf-project-cover__title', pOpenAnchor({ newTab: true, active: false })), { domain: /behance\.net/i });

// Adobe Fonts
api.mapkey('<Space>a', 'Activate font', () => pHints('.spectrum-ToggleSwitch-input'), { domain: /fonts\.adobe\.com/i });
api.mapkey('<Space>s', 'Favorite font', () => pHints('.favorite-toggle-icon'), { domain: /fonts\.adobe\.com/i });

// Wikipedia (incl. Wikimedia aliases)
const pWpDom = /^(www\.)?(simple\.)?wikipedia\.org|wiktionary\.org|wikiquote\.org|wikisource\.org|wikimedia\.org|mediawiki\.org|wikivoyage\.org|wikibooks\.org|wikinews\.org|wikiversity\.org|wikidata\.org|wiki\.archlinux\.org/i;
api.mapkey('<Space>s', 'Toggle simple version of current article', () => pWpToggleSimple(), { domain: pWpDom });
api.mapkey('<Space>a', 'View page', () => pHints('#bodyContent :not(sup):not(.mw-editsection) > a:not([rel=nofollow])'), { domain: pWpDom });
api.mapkey('<Space>e', 'View external link', () => pHints('a[rel=nofollow]'), { domain: pWpDom });
api.mapkey('<Space>ys', 'Copy article summary as Markdown', () => pWpMarkdownSummary(), { domain: pWpDom });
api.mapkey('<Space>R', 'View WikiRank for current article', () => pWpViewWikiRank(), { domain: pWpDom });

// Craigslist
api.mapkey('<Space>a', 'View listing', () => pHints('a.result-title'), { domain: /craigslist\.org/i });

// Nest Thermostat (path-scoped)
// path embedded in domain regex (SurfingKeys matches the full URL)
api.mapkey('=', 'Increment temperature', () => pNtAdjustTemp(1), { domain: /home\.nest\.com\/thermostat\/DEVICE_.*/i });
api.mapkey('-', 'Decrement temperature', () => pNtAdjustTemp(-1), { domain: /home\.nest\.com\/thermostat\/DEVICE_.*/i });
api.mapkey('<Space>h', 'Switch mode to Heat', () => pNtSetMode('heat'), { domain: /home\.nest\.com\/thermostat\/DEVICE_.*/i });
api.mapkey('<Space>c', 'Switch mode to Cool', () => pNtSetMode('cool'), { domain: /home\.nest\.com\/thermostat\/DEVICE_.*/i });
api.mapkey('<Space>r', 'Switch mode to Heat/Cool', () => pNtSetMode('range'), { domain: /home\.nest\.com\/thermostat\/DEVICE_.*/i });
api.mapkey('<Space>o', 'Switch mode to Off', () => pNtSetMode('off'), { domain: /home\.nest\.com\/thermostat\/DEVICE_.*/i });
api.mapkey('<Space>f', 'Switch fan On', () => pNtSetFan(1), { domain: /home\.nest\.com\/thermostat\/DEVICE_.*/i });
api.mapkey('<Space>F', 'Switch fan Off', () => pNtSetFan(0), { domain: /home\.nest\.com\/thermostat\/DEVICE_.*/i });

// rescript-lang.org
// /docs pages only (path embedded in domain regex)
api.mapkey('i', 'Focus search field', () => pReFocusSearch(), { domain: /rescript-lang\.org(\/docs(\/.*)?)?$/i });
api.mapkey('<Space>a', 'Open docs link', () => pHints("a[href^='/docs/']"), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>L', 'Open language manual', () => pOpenLink('/docs/manual/latest/introduction'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>R', 'Open ReScript + React docs', () => pOpenLink('/docs/react/latest/introduction'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>G', 'Open GenType docs', () => pOpenLink('/docs/gentype/latest/introduction'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>P', 'Open package index', () => pOpenLink('/packages'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>Y', 'Open playground', () => pOpenLink('/try'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>S', 'Open syntax lookup', () => pOpenLink('/syntax-lookup'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>F', 'Open community forum', () => pOpenLink('https://forum.rescript-lang.org/'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>A', 'Open API docs', () => pOpenLink('/docs/manual/latest/api'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>J', 'Open JS API docs', () => pOpenLink('/docs/js/latest/introduction'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>B', 'Open Belt API docs', () => pOpenLink('/docs/belt/latest/introduction'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('<Space>D', 'Open DOM API docs', () => pOpenLink('/docs/dom/latest/introduction'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('w', 'Scroll sidebar up', () => pReScrollSidebar('up'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('s', 'Scroll sidebar down', () => pReScrollSidebar('down'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('e', 'Scroll sidebar page up', () => pReScrollSidebar('pageUp'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('d', 'Scroll sidebar page down', () => pReScrollSidebar('pageDown'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('k', 'Scroll body up', () => pReScrollContent('up'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('j', 'Scroll body down', () => pReScrollContent('down'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('K', 'Scroll body page up', () => pReScrollContent('pageUp'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });
api.mapkey('J', 'Scroll body page down', () => pReScrollContent('pageDown'), { domain: /rescript-lang\.org\/docs(\/.*)?$/i });

// devdocs.io (sidebar/body scrolls; leader-less, domain-scoped)
const pDvDom = /devdocs\.io/i;
api.mapkey('w', 'Scroll sidebar up', () => pDvScrollSidebar('up'), { domain: pDvDom });
api.mapkey('s', 'Scroll sidebar down', () => pDvScrollSidebar('down'), { domain: pDvDom });
api.mapkey('e', 'Scroll sidebar page up', () => pDvScrollSidebar('pageUp'), { domain: pDvDom });
api.mapkey('d', 'Scroll sidebar page down', () => pDvScrollSidebar('pageDown'), { domain: pDvDom });
api.mapkey('k', 'Scroll body up', () => pDvScrollContent('up'), { domain: pDvDom });
api.mapkey('j', 'Scroll body down', () => pDvScrollContent('down'), { domain: pDvDom });
api.mapkey('K', 'Scroll body page up', () => pDvScrollContent('pageUp'), { domain: pDvDom });
api.mapkey('J', 'Scroll body page down', () => pDvScrollContent('pageDown'), { domain: pDvDom });

// ebay.com
api.mapkey('<Space>fs', 'Fakespot', () => pFakeSpot(), { domain: /ebay\.com/i });

// ikea.com
api.mapkey('<Space>d', 'Toggle Product Details', () => pIkToggleDetails(), { domain: /ikea\.com/i });
api.mapkey('<Space>i', 'Toggle Product Details', () => pIkToggleDetails(), { domain: /ikea\.com/i });
api.mapkey('<Space>r', 'Toggle Product Reviews', () => pIkToggleReviews(), { domain: /ikea\.com/i });
api.mapkey('<Space>C', 'Open Cart page', () => pOpenLink('/us/en/shoppingcart/'), { domain: /ikea\.com/i });
api.mapkey('<Space>P', 'Open Profile page', () => pOpenLink('/us/en/profile/login/'), { domain: /ikea\.com/i });
api.mapkey('<Space>F', 'Open Favorites page', () => pOpenLink('/us/en/favorites/'), { domain: /ikea\.com/i });
api.mapkey('<Space>O', 'Open Orders page', () => pOpenLink('/us/en/customer-service/track-manage-order/'), { domain: /ikea\.com/i });
// ========== Ported from sf-config (modular Surfingkeys config) ==========
// Dependency-free ports of the generally useful parts. Keys were renamed
// where the originals collide with this config, its search-alias prefixes
// (a*/ca*), or Surfingkeys 1.18 defaults. Helpers prefixed `sf`.

// ---- Fuzzy history search (from fzfFinder.js) ----
// The original fuzzy-searched a hardcoded demo array; here the extension's
// chrome.history permission is used via RUNTIME getHistory, and matching is
// a dependency-free subsequence fuzzy match (fuse.js is not available in
// this single-file config).

const sfFuzzyMatch = (q, s) => {
  q = q.toLowerCase();
  s = s.toLowerCase();
  let i = 0;
  for (let j = 0; i < q.length && j < s.length; j++) {
    if (q[i] === s[j]) i++;
  }
  return i === q.length;
};

api.mapkey('zz', 'Fuzzy search browsing history (fzf-style)', () => {
  api.RUNTIME('getHistory', { query: '', maxResults: 500, sortByMostUsed: true }, (response) => {
    const history = (response && response.history) || [];
    const overlay = document.createElement('div');
    Object.assign(overlay.style, {
      position: 'fixed', top: '20%', left: '50%', transform: 'translateX(-50%)',
      background: '#0d1824', color: '#6c7e96', borderRadius: '12px',
      boxShadow: '0 10px 40px rgba(0, 0, 0, 0.5)', zIndex: '9999',
      width: '560px', maxHeight: '60vh', padding: '16px', overflow: 'hidden',
      fontFamily: 'Iosevka, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
      fontSize: '14px',
    });
    const input = document.createElement('input');
    Object.assign(input.style, {
      width: '100%', padding: '8px 12px', marginBottom: '12px', boxSizing: 'border-box',
      background: '#000000', color: '#a5c1e6', border: '1px solid #223f73',
      borderRadius: '6px', outline: 'none', fontSize: '14px',
    });
    input.placeholder = 'Search history...';
    const list = document.createElement('div');
    Object.assign(list.style, {
      overflowY: 'auto', maxHeight: '45vh', display: 'flex', flexDirection: 'column', gap: '4px',
    });

    let entries = [];
    let selected = 0;

    const highlight = () => {
      entries.forEach(({ el }, i) => {
        el.style.background = i === selected ? '#1c334e' : '#0d1824';
        el.style.color = i === selected ? '#a5c1e6' : '#6c7e96';
      });
    };

    const render = (query) => {
      list.innerHTML = '';
      const q = query.trim();
      entries = history
        .filter((h) => !q || sfFuzzyMatch(q, (h.title || '') + ' ' + (h.url || '')))
        .slice(0, 15)
        .map((item) => {
          const el = document.createElement('div');
          Object.assign(el.style, {
            padding: '8px 12px', borderRadius: '6px', cursor: 'pointer',
            display: 'flex', gap: '8px', alignItems: 'baseline', userSelect: 'none',
          });
          const title = document.createElement('span');
          title.textContent = item.title || item.url || '';
          title.style.flex = '1';
          const url = document.createElement('span');
          url.textContent = item.url || '';
          url.style.opacity = '0.6';
          url.style.fontSize = '12px';
          el.appendChild(title);
          el.appendChild(url);
          el.onclick = () => {
            overlay.remove();
            window.location.href = item.url;
          };
          list.appendChild(el);
          return { el, item };
        });
      selected = 0;
      highlight();
    };

    input.oninput = (e) => render(e.target.value);
    input.onkeydown = (e) => {
      if (e.key === 'Escape') overlay.remove();
      else if (e.key === 'ArrowDown') {
        e.preventDefault();
        selected = Math.min(selected + 1, entries.length - 1);
        highlight();
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        selected = Math.max(selected - 1, 0);
        highlight();
      } else if (e.key === 'Enter' && entries[selected]) {
        e.preventDefault();
        overlay.remove();
        window.location.href = entries[selected].item.url;
      }
    };

    overlay.appendChild(input);
    overlay.appendChild(list);
    document.body.appendChild(overlay);
    input.focus();
    render('');
  });
});

// ---- URL yank & clipboard-path helpers (from urlYanker.js) ----
// y0-y4 copy URL parts without opening the omnibar; p,/p1-p3 rebuild the
// current URL with a path from the clipboard; pr replaces the URL entirely.
// (Original ag*/ap*/ar keys collide with the a<alias> search prefixes.)

const sfCopyUrlParts = (n) => {
  const parts = window.location.pathname.split('/').filter(Boolean);
  if (n === 0) {
    api.Clipboard.write(window.location.origin);
  } else if (parts.length > 0) {
    api.Clipboard.write(parts.slice(-n).join('/'));
  }
};
api.mapkey('y0', 'Copy origin of current URL', () => sfCopyUrlParts(0));
api.mapkey('y1', 'Copy last 1 path segment', () => sfCopyUrlParts(1));
api.mapkey('y2', 'Copy last 2 path segments', () => sfCopyUrlParts(2));
api.mapkey('y3', 'Copy last 3 path segments', () => sfCopyUrlParts(3));
api.mapkey('y4', 'Copy last 4 path segments', () => sfCopyUrlParts(4));
api.mapkey('y,', 'Open origin in new tab', () => {
  window.open(window.location.origin, '_blank');
});

const sfClipboardText = (clip) => {
  if (typeof clip === 'string') return clip;
  if (clip && typeof clip.data === 'string') return clip.data;
  return '';
};

const sfAppendClipboardToPath = (n) => {
  api.Clipboard.read((clip) => {
    const tail = sfClipboardText(clip).trim().replace(/^https?:\/\/[^/]*/i, '').replace(/^\/+/, '');
    if (!tail) return;
    const kept = n > 0 ? window.location.pathname.split('/').filter(Boolean).slice(0, n) : [];
    window.location.href = window.location.origin + '/' + kept.concat(tail).join('/');
  });
};
api.mapkey('p,', 'Append clipboard path to root', () => sfAppendClipboardToPath(0));
api.mapkey('p1', 'Append clipboard path after 1 segment', () => sfAppendClipboardToPath(1));
api.mapkey('p2', 'Append clipboard path after 2 segments', () => sfAppendClipboardToPath(2));
api.mapkey('p3', 'Append clipboard path after 3 segments', () => sfAppendClipboardToPath(3));

api.mapkey('pr', 'Replace current URL with clipboard content', () => {
  api.Clipboard.read((clip) => {
    let url = sfClipboardText(clip).trim();
    if (!url) return;
    if (!url.match(/^https?:\/\//)) {
      url = url.includes('localhost') || /^\d+\.\d+\.\d+\.\d+/.test(url)
        ? 'http://' + url
        : 'https://' + url;
    }
    try {
      new URL(url);
    } catch (e) {
      return;
    }
    window.location.href = url;
  });
});

// ---- Hints utilities (from hoverClick.js) ----
// cb: persistent click hints; Esc cancels the hint loop.
api.mapkey('cb', 'Persistent click hints', function sfClickHints() {
  api.Hints.create(
    'a, button, select, input, textarea, summary, *[onclick], *[contenteditable=true], *[role=button], *[role=link], *[role=menuitem], *[role=option], *[role=switch], *[role=tab], *[role=checkbox], *[role=combobox], *[role=menuitemcheckbox], *[role=menuitemradio]',
    (el) => {
      el.click();
      setTimeout(sfClickHints, 200);
    },
  );
});

// ch: hover an element via hints (mouseover/mouseenter + focus).
api.mapkey('ch', 'Hover element via hints', () => {
  api.Hints.create('*', (el) => {
    el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true, cancelable: true, view: window }));
    el.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, cancelable: true, view: window }));
    if (typeof el.focus === 'function') el.focus();
  });
});

// cx: reveal hidden elements via hints (renamed from ca — ca is a prefix of
// the ca<alias> clipboard-search keys).
api.mapkey('cx', 'Reveal hidden elements via hints', () => {
  api.Hints.create('*', (el) => {
    el.style.display = 'block';
    el.style.visibility = 'visible';
    el.style.opacity = '1';
    el.hidden = false;
  });
});

// ci: open a link in an incognito window (from hoverClick.js 'of'; 'o' is
// the custom address-bar mapping, and 's' is now page-scroll).
api.mapkey('ci', 'Open link in incognito window', () => {
  api.Hints.create('*[href]', (el) => {
    api.RUNTIME('openIncognito', { url: el.href });
  });
});

// ---- Image yank (from imgYank.js) ----
api.mapkey('cm', 'Copy image as Markdown', () => {
  api.Hints.create('img[src]', (el) => {
    api.Clipboard.write('![' + (el.alt || 'image') + '](' + el.src + ')');
  });
});

// ---- YouTube language toggler (from yt.js; URL-param method only) ----
// ayy toggles captions between Original and English (USA); ayo/ayu set them
// explicitly; ays shows the current state. (Original ayt dropped — 'ayt' is
// taken by the a<alias> youtube search prefix.)

const sfYtSetLang = (lang) => {
  if (!window.location.hostname.includes('youtube.com') || !window.location.pathname.includes('/watch')) {
    api.Front.showBanner('Only works on YouTube watch pages');
    return;
  }
  const url = new URL(window.location.href);
  if (lang === 'original') {
    url.searchParams.delete('cc_load_policy');
    url.searchParams.delete('cc_lang_pref');
  } else {
    url.searchParams.set('cc_load_policy', '1');
    url.searchParams.set('cc_lang_pref', 'en');
  }
  window.location.href = url.toString();
};
const sfYtCurrentLang = () => {
  const p = new URLSearchParams(window.location.search);
  return p.get('cc_load_policy') === '1' && p.get('cc_lang_pref') === 'en' ? 'en' : 'original';
};
api.mapkey('ayy', 'Toggle YouTube captions Original/English', () => {
  sfYtSetLang(sfYtCurrentLang() === 'en' ? 'original' : 'en');
});
api.mapkey('ayo', 'Set YouTube captions to Original', () => sfYtSetLang('original'));
api.mapkey('ayu', 'Set YouTube captions to English (USA)', () => sfYtSetLang('en'));
api.mapkey('ays', 'Show current YouTube caption language', () => {
  api.Front.showBanner('Captions: ' + (sfYtCurrentLang() === 'en' ? 'English (USA)' : 'Original'));
});

// zx closes every tab on the current host (from tab.js 'sxx'; 's' is now
// page-scroll, so the key moved to the free z* family).
api.mapkey('zx', 'Close all tabs from same host', () => {
  api.RUNTIME('getTabs', { queryInfo: {} }, (response) => {
    api.RUNTIME('getTabs', { queryInfo: { active: true, currentWindow: true } }, (active) => {
      const current = active.tabs && active.tabs[0];
      if (!current) return;
      let host;
      try {
        host = new URL(current.url).hostname;
      } catch (e) {
        return;
      }
      (response.tabs || []).forEach((tab) => {
        try {
          if (new URL(tab.url).hostname === host) {
            api.RUNTIME('removeTab', { tabId: tab.id });
          }
        } catch (e) {
          // ignore tabs with unparseable URLs
        }
      });
    });
  });
});

// ---- Clock (from testDate.js; dayjs replaced with native Date) ----
api.mapkey('g,', 'Show current date and time', () => {
  api.Front.showBanner('Now: ' + new Date().toLocaleString());
});
