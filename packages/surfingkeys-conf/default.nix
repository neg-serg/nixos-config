{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  customConfig ? null,
}:
buildNpmPackage {
  pname = "surfingkeys-pkg";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "b0o";
    repo = "surfingkeys-conf";
    rev = "master"; # Using master as it's a config repo, often ahead of releases
    hash = "sha256-udcgfQczvx6ZVr2RqdXdD5u0+lZTDf+SakxGGM7Rk3Q=";
  };

  npmDepsHash = "sha256-qATWB1XQaTn6ltaCuH9EbrD1WCyDy5czwTmDAIoGD+s=";

  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    cat > ./src/conf.priv.js <<EOF
    const handler = { get: (target, prop) => (prop in target ? target[prop] : "") };
    const keys = new Proxy({}, handler);
    export default new Proxy({ keys }, handler);
    EOF
    
    # Inject custom mappings if provided
    if [ -n "${toString customConfig}" ] && [ -f "${toString customConfig}" ]; then
      echo "Injecting custom mappings from ${toString customConfig}..."
      # Extract global settings (5-11) but NOT the theme (14-212)
      # This restores settings.focusFirstCandidate, settings.omnibarSuggestion etc.
      sed -n '5,11p' "${toString customConfig}" >> ./src/index.js
      # Extract mappings (214-end)
      sed -n '214,$p' "${toString customConfig}" >> ./src/index.js

      # Smart Omnibar logic: If input contains dots and no spaces, treat as URL.
      # Otherwise, use the default search engine (DuckDuckGo).
      cat >> ./src/index.js <<JS

const smartDispatch = (input, newTab) => {
  const isURL = input.includes(".") && !input.includes(" ");
  if (isURL) {
    const url = input.match(/^https?:\/\//) ? input : "https://" + input;
    if (newTab) {
      RUNTIME("openLink", { tab: { tabbed: true }, url });
    } else {
      window.location.href = url;
    }
  } else {
    const searchURL = "https://duckduckgo.com/?q=" + encodeURIComponent(input);
    if (newTab) {
      RUNTIME("openLink", { tab: { tabbed: true }, url: searchURL });
    } else {
      window.location.href = searchURL;
    }
  }
};

mapkey("t", "Smart Omnibar (New Tab)", () => {
  Front.openOmnibar({
    type: "SearchEngine",
    extra: "dd",
    onEnter: (input) => smartDispatch(input, true),
  });
});

mapkey("o", "Smart Omnibar (Current Tab)", () => {
  Front.openOmnibar({
    type: "SearchEngine",
    extra: "dd",
    onEnter: (input) => smartDispatch(input, false),
  });
});
JS
    fi

    cat > build.mjs <<EOF
    import webpack from 'webpack';
    import config from './webpack.config.js';
    import path from 'path';
    import { fileURLToPath } from 'url';

    const __dirname = path.dirname(fileURLToPath(import.meta.url));

    config.mode = 'production';
    config.output = {
      path: path.join(__dirname, 'build'),
      filename: 'surfingkeys.js',
    };

    webpack(config, (err, stats) => {
      if (err) {
        console.error(err);
        process.exit(1);
      }
      if (stats.hasErrors()) {
        console.error(stats.toString());
        process.exit(1);
      }
      console.log('Build complete');
    });
    EOF
    node build.mjs
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/surfingkeys
    cp build/surfingkeys.js $out/share/surfingkeys/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Maddison's SurfingKeys Configuration";
    homepage = "https://github.com/b0o/surfingkeys-conf";
    license = licenses.mit;
    maintainers = [];
    platforms = platforms.all;
  };
}
