# Shared Python package list — single source of truth for the system python
# env (modules/dev/python/pkgs.nix) and the python devshell
# (flake/devshells/python.nix). Add/remove packages HERE, not in both files.
{ }:
{
  # ps: -> [ ... ] — package list for python3.withPackages
  myPythonPackages =
    ps: with ps; [
      # Base utilities
      colored
      docopt
      numpy
      pillow
      psutil
      requests
      tabulate
      rich # pretty console output (tables, syntax highlighting)
      tqdm # progress bars for long loops
      humanize # human-readable numbers/dates/sizes
      filetype # detect file type by magic bytes
      python-dotenv # load .env config files
      watchdog # file/dir change monitoring

      # Data and parsing
      beautifulsoup4
      orjson
      lxml # fast HTML/XML parsing (beautifulsoup4 backend)
      pyyaml # YAML config files
      jinja2 # templating
      httpx # modern HTTP client (HTTP/2, async-ready)

      # Web scraping / async networking
      aiohttp # async HTTP client/server
      websockets # WebSocket protocol client/server
      parsel # XPath/CSS selectors for scraping
      selectolax # fast C-based HTML parser (scraping)

      # Tool integration
      dbus-python
      pynvim
      pexpect # expect-style process automation (spawn, interact)
      plumbum # shell commands as Python objects
      typer # CLI apps from type-annotated functions

      # Debugging (nvim-dap: python3 -m debugpy.adapter)
      debugpy

      # Media/Type related (used by local-bin)
      fontforge
      fonttools
      mutagen

      # ML / misc (devshell and scripts)
      annoy
      scikit-learn # classic ML algorithms (classify/cluster/regress)
      sympy # symbolic mathematics
      tokenizers # fast HuggingFace tokenization
      sentencepiece # subword tokenizer (BPE/unigram)

      # Image/vision (cv2 and friends)
      opencv4 # cv2: OpenCV bindings for image/video processing
      matplotlib # plotting / image visualization
      pytesseract # OCR wrapper around the system-wide tesseract engine
      piexif # EXIF metadata read/write for JPEG

      # Scientific/data
      scipy # scientific computing (signal, stats, linear algebra)
      pandas # tabular data analysis

      # Audio
      pydub # audio manipulation (needs ffmpeg binary)
      soundfile # libsndfile bindings (WAV/FLAC/OGG read/write)

      # Testing (devshell and scripts)
      pytest # test runner
      hypothesis # property-based testing
      coverage # code coverage measurement
      tox # test env matrix runner
    ];
}
