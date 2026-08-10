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
    https.get(url, { headers: { "User-Agent": "vicinae-wallhaven/1.0" } }, function (res) {
      var data = "";
      res.on("data", function (chunk) { data += chunk; });
      res.on("end", function () {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error("Failed to parse API response")); }
      });
    }).on("error", reject);
  });
}

function downloadFile(url, dest) {
  return new Promise(function (resolve, reject) {
    var file = fs.createWriteStream(dest);
    https.get(url, { headers: { "User-Agent": "vicinae-wallhaven/1.0" } }, function (res) {
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

// Map MIME type -> file extension (wallhaven returns file_type like "image/jpeg")
function extFromMime(mime) {
  if (!mime) return "jpg";
  var map = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/gif": "gif",
    "image/webp": "webp",
    "image/bmp": "bmp",
    "image/avif": "avif",
  };
  return map[mime] || "jpg";
}

function WallhavenSearch() {
  var _a = React.useState([]), results = _a[0], setResults = _a[1];
  var _b = React.useState(false), loading = _b[0], setLoading = _b[1];
  var _c = React.useState(""), searchText = _c[0], setSearchText = _c[1];
  var _d = React.useState(""), query = _d[0], setQuery = _d[1];
  var _e = React.useState(null), error = _e[0], setError = _e[1];
  var _f = React.useState({}), thumbs = _f[0], setThumbs = _f[1];
  var prefs = api.getPreferenceValues();
  var home = os.homedir();
  var dlDir = prefs.download_dir ? prefs.download_dir.replace(/^~/, home) : path.join(home, "pic", "wl");
  var cacheDir = path.join(home, ".cache", "vicinae", "wallhaven", "thumbs");

  var doSearch = React.useCallback(function (q) {
    if (!q || !q.trim()) return;
    setLoading(true);
    setError(null);
    setQuery(q);

    var purity = prefs.default_purity || "sfw";
    var sort = prefs.default_sort || "random";
    var apiKey = prefs.api_key || "";

    var params = new URLSearchParams({
      q: q,
      sorting: sort,
      purity: purity === "sfw+sketchy" ? "110" : "100",
      categories: "111",
      atleast: "1920x1080",
    });
    if (apiKey) params.set("apikey", apiKey);

    try { fs.mkdirSync(cacheDir, { recursive: true }); } catch (_) {}
    try { fs.mkdirSync(dlDir, { recursive: true }); } catch (_) {}
    fetchJSON("https://wallhaven.cc/api/v1/search?" + params.toString()).then(function (data) {
      if (!data || !data.data) {
        setResults([]);
        setError("No results or API error");
        setLoading(false);
        return;
      }
      setResults(data.data);
      setLoading(false);

      // Download thumbnails in parallel for list previews
      try { fs.mkdirSync(cacheDir, { recursive: true }); } catch (_) {}
      var seen = {};
      data.data.forEach(function (img) {
        var thumbUrl = img.thumbs && (img.thumbs.large || img.thumbs.small);
        if (!thumbUrl || seen[img.id]) return;
        seen[img.id] = true;
        var dest = path.join(cacheDir, img.id + ".jpg");
        if (fs.existsSync(dest)) {
          setThumbs(function (t) { var n = {}; n[img.id] = dest; return Object.assign({}, t, n); });
          return;
        }
        downloadFile(thumbUrl, dest).then(function () {
          setThumbs(function (t) { var n = {}; n[img.id] = dest; return Object.assign({}, t, n); });
        }).catch(function () {});
      });
    }).catch(function (e) {
      setError(e.message);
      setResults([]);
      setLoading(false);
    });
  }, [prefs, cacheDir]);

  // Debounced search: fire doSearch 800ms after typing stops
  React.useEffect(function () {
    if (!searchText || !searchText.trim()) return;
    var timer = setTimeout(function () { doSearch(searchText); }, 800);
    return function () { clearTimeout(timer); };
  }, [searchText]);

  var items = React.useMemo(function () {
    if (!results.length) return [];

    return results.map(function (img) {
      var resolution = img.resolution || "?";
      var id = img.id || "?";
      var thumbPath = thumbs[id];
      var icon = thumbPath ? { source: thumbPath } : api.Icon.Image;

      return React.createElement(api.List.Item, {
        key: id,
        id: "wh-" + id,
        icon: icon,
        subtitle: (img.tags || []).map(function (t) { return t.name; }).join(", ") || "No tags",
        accessories: [
          { text: String(img.favorites || 0), icon: api.Icon.Star }
        ],
        actions: React.createElement(api.ActionPanel, null,
          React.createElement(api.Action, {
            title: "Set as Wallpaper",
            icon: api.Icon.Desktop,
            onAction: function () {
              return Promise.resolve().then(function () {
                var filepath = path.join(dlDir, "wallhaven-" + img.id + "." + extFromMime(img.file_type));
                return api.showToast({
                  style: api.Toast.Style.Animated,
                  title: "Downloading...",
                  message: resolution,
                }).then(function () {
                  return downloadFile(img.path, filepath);
                }).then(function () {
                  cp.execSync('wl img "' + filepath + '"', { stdio: "ignore", timeout: 10000 });
                  return api.showToast({
                    style: api.Toast.Style.Success,
                    title: "Wallpaper set",
                    message: img.id,
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
              cp.exec('xdg-open "' + img.url + '"', { stdio: "ignore" });
            }
          }),
          React.createElement(api.Action.CopyToClipboard, {
            title: "Copy URL",
            content: img.url,
          })
        )
      });
    });
  }, [results, dlDir, thumbs]);

  return React.createElement(api.List, {
    isLoading: loading,
    searchBarPlaceholder: "Search Wallhaven...",
    onSearchTextChange: setSearchText
  },
    error && !loading
      ? React.createElement(api.List.EmptyView, {
          icon: api.Icon.Exclamationmark,
          title: "Search Error",
          description: error
        })
      : !loading && !error && query && results.length === 0
        ? React.createElement(api.List.EmptyView, {
            icon: api.Icon.MagnifyingGlass,
            title: "No results",
            description: 'No wallpapers found for "' + query + '"'
          })
        : !query && !loading
          ? React.createElement(api.List.EmptyView, {
              icon: api.Icon.MagnifyingGlass,
              title: "Search Wallhaven",
              description: "Type a query and press Enter to search"
            })
          : React.createElement(api.List.Section, { title: query ? "Results: " + query + " (" + results.length + ")" : "Results" },
              items
            )
  );
}

module.exports = { default: WallhavenSearch };
