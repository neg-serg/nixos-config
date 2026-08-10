"use strict";

// Vicinae patches Module.prototype.require to provide these.
// MUST use CommonJS (not ESM) for the patch to work.
var React = require("react");
var https = require("https");
var cp = require("child_process");
var fs = require("fs");
var path = require("path");
var os = require("os");
var api = require("@vicinae/api");

function fetchJSON(url) {
  return new Promise(function (resolve, reject) {
    https.get(url, { headers: { "User-Agent": "vicinae-unsplash/1.0" } }, function (res) {
      var data = "";
      res.on("data", function (chunk) { data += chunk; });
      res.on("end", function () {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error("Failed to parse API response (" + res.statusCode + ")")); }
      });
    }).on("error", reject);
  });
}

function downloadFile(url, dest) {
  return new Promise(function (resolve, reject) {
    var file = fs.createWriteStream(dest);
    https.get(url, { headers: { "User-Agent": "vicinae-unsplash/1.0" } }, function (res) {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        file.close();
        try { fs.unlinkSync(dest); } catch (_) {}
        return downloadFile(res.headers.location, dest).then(resolve, reject);
      }
      res.pipe(file);
      file.on("finish", function () { file.close(resolve); });
    }).on("error", function (e) {
      try { fs.unlinkSync(dest); } catch (_) {}
      reject(e);
    });
  });
}

// Resolve access key: preference -> env -> ~/.gemini/unsplash.key (same as `sw`)
function resolveAccessKey(prefKey) {
  if (prefKey && prefKey.trim()) return prefKey.trim();
  if (process.env.UNSPLASH_ACCESS_KEY) return process.env.UNSPLASH_ACCESS_KEY;
  try {
    var f = path.join(os.homedir(), ".gemini", "unsplash.key");
    if (fs.existsSync(f)) {
      var k = fs.readFileSync(f, "utf8").trim();
      if (k) return k;
    }
  } catch (_) {}
  return null;
}

function UnsplashSearch() {
  var _a = React.useState([]), results = _a[0], setResults = _a[1];
  var _b = React.useState(false), loading = _b[0], setLoading = _b[1];
  var _c = React.useState(""), searchText = _c[0], setSearchText = _c[1];
  var _d = React.useState(""), query = _d[0], setQuery = _d[1];
  var _e = React.useState(null), error = _e[0], setError = _e[1];
  var _f = React.useState({}), thumbs = _f[0], setThumbs = _f[1];
  var prefs = api.getPreferenceValues();
  var home = os.homedir();
  var dlDir = prefs.download_dir ? prefs.download_dir.replace(/^~/, home) : path.join(home, "pic", "wl");
  var cacheDir = path.join(home, ".cache", "vicinae", "unsplash", "thumbs");
  var accessKey = resolveAccessKey(prefs.access_key);

  var doSearch = React.useCallback(function (q) {
    if (!q || !q.trim()) return;
    setLoading(true);
    setError(null);
    setQuery(q);

    var params = new URLSearchParams({
      query: q,
      per_page: "30",
      orientation: "landscape",
      client_id: accessKey,
    });

    fetchJSON("https://api.unsplash.com/search/photos?" + params.toString()).then(function (data) {
      if (!data || !data.results) {
        setResults([]);
        setError(data && data.errors ? data.errors.join(" ") : "No results or API error");
        setLoading(false);
        return;
      }
      setResults(data.results);
      setLoading(false);

      // Download thumbnails in parallel for grid previews
      try { fs.mkdirSync(cacheDir, { recursive: true }); } catch (_) {}
      var seen = {};
      data.results.forEach(function (photo) {
        if (!photo.urls || !photo.urls.thumb || seen[photo.id]) return;
        seen[photo.id] = true;
        var dest = path.join(cacheDir, photo.id + ".jpg");
        if (fs.existsSync(dest)) {
          setThumbs(function (t) { var n = {}; n[photo.id] = dest; return Object.assign({}, t, n); });
          return;
        }
        downloadFile(photo.urls.thumb, dest).then(function () {
          setThumbs(function (t) { var n = {}; n[photo.id] = dest; return Object.assign({}, t, n); });
        }).catch(function () {});
      });
    }).catch(function (e) {
      setError(e.message);
      setResults([]);
      setLoading(false);
    });
  }, [prefs, cacheDir, accessKey]);

  // Debounced search: fire doSearch 800ms after typing stops
  React.useEffect(function () {
    if (!searchText || !searchText.trim()) return;
    var timer = setTimeout(function () { doSearch(searchText); }, 800);
    return function () { clearTimeout(timer); };
  }, [searchText]);

  var items = React.useMemo(function () {
    if (!results.length) return [];

    return results.map(function (photo) {
      var id = photo.id || "?";
      var thumbPath = thumbs[id];
      var content = thumbPath ? { source: thumbPath } : undefined;
      var resolution = photo.width && photo.height
        ? photo.width + "x" + photo.height
        : "";

      return React.createElement(api.Grid.Item, {
        key: id,
        id: "us-" + id,
        content: content,
        title: (photo.user && photo.user.name) || id,
        subtitle: resolution || undefined,
        actions: React.createElement(api.ActionPanel, null,
          React.createElement(api.Action, {
            title: "Set as Wallpaper",
            icon: api.Icon.Desktop,
            onAction: function () {
              return Promise.resolve().then(function () {
                var filepath = path.join(dlDir, "unsplash-" + id + ".jpg");
                return api.showToast({
                  style: api.Toast.Style.Animated,
                  title: "Downloading...",
                  message: resolution || id,
                }).then(function () {
                  return downloadFile(photo.urls.full, filepath);
                }).then(function () {
                  cp.execSync('wl img "' + filepath + '"', { stdio: "ignore", timeout: 10000 });
                  return api.showToast({
                    style: api.Toast.Style.Success,
                    title: "Wallpaper set",
                    message: id,
                  });
                });
              }).catch(function (e) {
                return api.showToast({
                  style: api.Toast.Style.Failure,
                  title: "Failed",
                  message: e.message,
                });
              });
            }
          }),
          React.createElement(api.Action, {
            title: "Open in Browser",
            icon: api.Icon.Globe,
            onAction: function () {
              var page = photo.links && photo.links.html;
              if (page) cp.exec('xdg-open "' + page + '"', { stdio: "ignore" });
            }
          }),
          React.createElement(api.Action.CopyToClipboard, {
            title: "Copy Page URL",
            content: (photo.links && photo.links.html) || "",
          })
        )
      });
    });
  }, [results, dlDir, thumbs]);

  return React.createElement(api.Grid, {
    isLoading: loading,
    searchBarPlaceholder: "Search Unsplash...",
    onSearchTextChange: setSearchText,
    columns: 3,
    aspectRatio: "16/9",
    fit: api.Grid.Fit.Fill,
    throttle: true
  },
    !accessKey
      ? React.createElement(api.List.EmptyView, {
          icon: api.Icon.Key,
          title: "Unsplash API key required",
          description: "Set access_key in extension preferences, or save it to ~/.gemini/unsplash.key / UNSPLASH_ACCESS_KEY"
        })
      : error && !loading
        ? React.createElement(api.List.EmptyView, {
            icon: api.Icon.Exclamationmark,
            title: "Search Error",
            description: error
          })
        : !loading && !error && query && results.length === 0
          ? React.createElement(api.List.EmptyView, {
              icon: api.Icon.MagnifyingGlass,
              title: "No results",
              description: 'No photos found for "' + query + '"'
            })
          : !query && !loading
            ? React.createElement(api.List.EmptyView, {
                icon: api.Icon.MagnifyingGlass,
                title: "Search Unsplash",
                description: "Type a query to search"
              })
            : items
  );
}

module.exports = { default: UnsplashSearch };
