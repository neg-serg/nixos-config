{
  lib,
  python312,
  fetchPypi,
  fetchurl,
  libmaxminddb,
  ...
}:
let
  # tmd-top pins exact PyPI versions of its runtime deps (textual==1.0.0 etc.).
  # nixpkgs' current textual/rich/geoip2/maxminddb are far newer and incompatible:
  # the app imports textual internals (textual._two_way_dict, _styles_cache,
  # cache.LRUCache) that were removed upstream, and textual 1.0.0 predates
  # Python 3.13 (typing_extensions 4.9.0 crashes there: ParamSpec is immutable).
  # So build the whole stack on python312 with the exact pinned versions.
  #
  # The pinned packages are defined as private derivations here — deliberately NOT
  # injected into python312Packages via packageOverrides: overriding set-level
  # typing-extensions to 4.9.0 breaks other set packages (e.g. pytest-asyncio
  # needs >= 4.12 when poetry-core builds with its test suite).
  pypi = python312.pkgs;

  typing-extensions = pypi.buildPythonPackage {
    pname = "typing-extensions";
    version = "4.9.0";
    format = "pyproject";
    # fetchPypi would 404 (the PyPI project name is "typing_extensions").
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/0c/1d/eb26f5e75100d531d7399ae800814b069bc2ed2a7410834d57374d010d96/typing_extensions-4.9.0.tar.gz";
      hash = "sha256-I0ePiMN/J9dqyK7myQUBehQ7CxuIbDyfZrwv2U+fV4M=";
    };
    nativeBuildInputs = [ pypi.flit-core ];
    doCheck = false;
  };

  rich = pypi.buildPythonPackage {
    pname = "rich";
    version = "13.7.1";
    format = "pyproject";
    src = fetchPypi {
      pname = "rich";
      version = "13.7.1";
      hash = "sha256-m+MIyx/i8fV9Z86Z6Vrzih4rxxrZgTsOJHz3/7zDpDI=";
    };
    nativeBuildInputs = [ pypi.poetry-core ];
    propagatedBuildInputs = [
      (noCheck pypi.markdown-it-py)
      (noCheck pypi.pygments)
      typing-extensions
    ];
    doCheck = false;
    pythonImportsCheck = [ "rich" ];
  };

  textual = pypi.buildPythonPackage {
    pname = "textual";
    version = "1.0.0";
    format = "pyproject";
    src = fetchPypi {
      pname = "textual";
      version = "1.0.0";
      hash = "sha256-vsn+Y1R8HFUladG3XTCQOLfUVsA/ht+jcG3bCZsVE5k=";
    };
    nativeBuildInputs = [ pypi.poetry-core ];
    # markdown-it-py[linkify,plugins] extra — nixpkgs' markdown-it-py does not
    # carry the extras, so add linkify-it-py / mdit-py-plugins explicitly.
    propagatedBuildInputs = [
      rich
      (noCheck pypi.markdown-it-py)
      (noCheck pypi.linkify-it-py)
      (noCheck pypi.mdit-py-plugins)
      (noCheck pypi.platformdirs)
    ];
    doCheck = false;
    pythonImportsCheck = [ "textual" ];
  };

  # nixpkgs deps of the pinned stack, minus their test suites: with
  # substitute=false their checkInputs (matplotlib, sphinx, xvfb, ...) would
  # otherwise be built from source for nothing — they are runtime libs only.
  # Recurses through `dependencies`/`propagatedBuildInputs`/`nativeBuildInputs`
  # (python-only; non-python entries like hooks/C libs are kept as-is).
  # nixpkgs' typing-extensions is replaced with the pinned 4.9.0 so the closure
  # does not end up with two versions of typing_extensions.
  noCheck =
    pkg:
    let
      # Replace nixpkgs' typing-extensions with the pinned 4.9.0 (avoids a
      # closure with two typing_extensions versions), recurse into python deps,
      # keep non-python entries (hooks/C libs) as-is.
      fix =
        d:
        if d == pypi.typing-extensions then
          typing-extensions
        else if d ? overridePythonAttrs then
          noCheck d
        else
          d;
    in
    pkg.overridePythonAttrs (old: {
      doCheck = false;
      nativeBuildInputs = map fix (old.nativeBuildInputs or [ ]);
      build-system = map fix (old.build-system or [ ]);
      dependencies = map fix (old.dependencies or [ ]);
      propagatedBuildInputs = map fix (old.propagatedBuildInputs or [ ]);
    });

  # nixpkgs' aiohappyeyeballs folds its *docs* extras (furo/myst-parser/sphinx)
  # into build-system; keep only the real build backend and drop the doc output
  # so the sphinx closure does not get built for nothing.
  aiohappyeyeballs = pypi.aiohappyeyeballs.overridePythonAttrs (_: {
    doCheck = false;
    outputs = [ "out" ];
    build-system = [ pypi.poetry-core ];
  });

  aiohttp = pypi.aiohttp.overridePythonAttrs (old: {
    doCheck = false;
    dependencies = map (
      d: if d == pypi.aiohappyeyeballs then aiohappyeyeballs else noCheck d
    ) old.dependencies;
  });

  # geoip2 4.8.0 wants maxminddb>=2.5.1,<3.0; nixpkgs ships 3.0.0, so pin 2.6.2.
  maxminddb = pypi.buildPythonPackage {
    pname = "maxminddb";
    version = "2.6.2";
    format = "setuptools";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/9f/9e/7806bf76d917182a4f4a08325f66eee6f32fe1123398789ba2547b5d3f3e/maxminddb-2.6.2.tar.gz";
      hash = "sha256-fYQtMuJiCryJS315paEAemnfLGzyeaBrlMnDkT9m8mQ=";
    };
    buildInputs = [ libmaxminddb ];
    doCheck = false;
    pythonImportsCheck = [ "maxminddb" ];
  };

  geoip2 = pypi.buildPythonPackage {
    pname = "geoip2";
    version = "4.8.0";
    format = "pyproject";
    src = fetchPypi {
      pname = "geoip2";
      version = "4.8.0";
      hash = "sha256-3ZzBgLfUFyQkDqSB1dU5FJ5lsjT2QoKyMbkXB5SprDU=";
    };
    nativeBuildInputs = [
      pypi.setuptools
      pypi.setuptools-scm
      pypi.wheel
    ];
    propagatedBuildInputs = [
      aiohttp
      maxminddb
      (noCheck pypi.requests)
    ];
    doCheck = false;
    pythonImportsCheck = [ "geoip2" ];
  };
in
pypi.buildPythonApplication rec {
  pname = "tmd-top";
  version = "2.2.0";
  format = "setuptools"; # sdist has setup.py/setup.cfg, no pyproject.toml
  # fetchPypi would build packages/source/t/tmd-top/tmd-top-2.2.0.tar.gz (404 —
  # the project name on PyPI is "tmd_top"), so fetch the exact hash-layout URL.
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/60/cf/d81710db5594e8b6ebd71e9ba185d12209e7427c686f3f6d30df974bc0ba/tmd_top-2.2.0.tar.gz";
    hash = "sha256-SGxcM7CawI/uBvkg/u+pC1tD50DBlJL1FqzYm8La2+A=";
  };

  # Bundles data/GeoLite2-City.mmdb and data/tmd-top.db via package_data in setup.py.
  nativeBuildInputs = [
    pypi.setuptools
    pypi.wheel
  ];
  propagatedBuildInputs = [
    textual
    typing-extensions
    rich
    geoip2
  ];
  doCheck = false;
  # Import the real module too: validates the full pinned stack (textual internals,
  # geoip2 Reader) at build time.
  pythonImportsCheck = [
    "tmd_top"
    "tmd_top.main"
  ];

  meta = with lib; {
    description = "Real-time Linux network traffic monitor with per-IP connection and bandwidth breakdown (TUI)";
    homepage = "https://gitee.com/Davin168/tmd-top";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "tmd-top";
    maintainers = [ ];
  };
}
