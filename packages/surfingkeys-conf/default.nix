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
    echo "export default {};" > ./src/conf.priv.js
    
    # Inject custom mappings if provided
    if [ -n "${toString customConfig}" ] && [ -f "${toString customConfig}" ]; then
      echo "Injecting custom mappings from ${toString customConfig}..."
      # Extract from line 214 (// ========== Mappings ==========) to end
      # We skip the settings/theme part of the old file to prefer b0o's look
      sed -n '214,$p' "${toString customConfig}" >> ./src/index.js
    fi

    cat > build.mjs <<EOF
    import webpack from 'webpack';
    import config from './webpack.config.js';
    import path from 'path';
    import { fileURLToPath } from 'url';

    const __dirname = path.dirname(fileURLToPath(import.meta.url));

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
