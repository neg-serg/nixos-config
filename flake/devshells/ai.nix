{ pkgs, ... }:
let
  # Offline translation stack: CTranslate2 runtime, sentencepiece tokenizers and
  # huggingface-hub for pulling model conversions. Replaces the hand-kept
  # ~/src/ai-tools/venv-translate pip tree (deleted 2026-10-23): the venv was
  # bound to the system python3.12 and lost its interpreter on the next python
  # bump, which is exactly what killed the marker/got-ocr venvs next to it.
  translateEnv = pkgs.python3.withPackages (ps: [
    ps.ctranslate2 # fast inference engine for transformer models (NLLB/opus-mt)
    ps.sentencepiece # tokenizer used by the CT2/marian models
    ps.huggingface-hub # model download/resolve helper
  ]);
  # Playwright 1.63.0: `playwright-test` carries @playwright/test plus the
  # playwright/playwright-core bindings, and playwright-driver.browsers the
  # browser bundles built for that exact version. `npx playwright install` does
  # not work on NixOS (the downloaded chromium dlopens the host glib and dies on
  # libglib-2.0.so.0), so the shell points PLAYWRIGHT_BROWSERS_PATH at the store
  # copy instead — no download step, no version drift between driver and browser.
  playwrightEnv = pkgs.playwright-test;
in
{
  packages = [
    translateEnv
    playwrightEnv
    # Docling (~3.9 GiB with its layout/table models): PDF/DOCX → Markdown.
    # Moved out of the system closure; also `nix run .#docling -- file.pdf`.
    pkgs.neg.docling-env
    pkgs.nodejs # runtime for the Playwright suites (@playwright/test needs >= 20)
    pkgs.chromium # system browser: CDP attach to a live Vivaldi/Chromium profile
  ];
  env = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
    # Lets a bare `node script.mjs` resolve @playwright/test and playwright
    # without a local node_modules tree: the store copy is the module root.
    NODE_PATH = "${playwrightEnv}/lib/node_modules";
  };
  shellHook = ''
    echo "ai shell: playwright $(playwright --version 2>/dev/null || echo 'missing')"
    echo "          browsers: $PLAYWRIGHT_BROWSERS_PATH"
  '';
}
