{
  config,
  lib,
  pkgs,
  ...
}:
let
  homeDir = config.users.users.neg.home;
  dataHome = "${homeDir}/.local/share";
  configHome = "${homeDir}/.config";
  cacheHome = "${homeDir}/.cache";
  stateHome = "${homeDir}/.local/state";
in
{
  environment.variables = {
    # NixOS handles standard XDG variables by default if xdg.enable is true,
    # but we force them here to match standard profile config
    XDG_CACHE_HOME = lib.mkForce cacheHome;
    XDG_CONFIG_HOME = lib.mkForce configHome;
    XDG_DATA_HOME = lib.mkForce dataHome;
    XDG_DESKTOP_DIR = lib.mkForce "${homeDir}/.local/desktop";
    XDG_DOCUMENTS_DIR = lib.mkForce "${homeDir}/doc";
    XDG_DOWNLOAD_DIR = lib.mkForce "${homeDir}/dw";
    XDG_MUSIC_DIR = lib.mkForce "${homeDir}/music";
    XDG_PICTURES_DIR = lib.mkForce "${homeDir}/pic";
    XDG_PUBLICSHARE_DIR = lib.mkForce "${homeDir}/.local/public";
    XDG_STATE_HOME = lib.mkForce "${homeDir}/.local/state";
    XDG_TEMPLATES_DIR = lib.mkForce "${homeDir}/.local/templates";
    XDG_VIDEOS_DIR = lib.mkForce "${homeDir}/vid";
    # XDG_RUNTIME_DIR is managed by systemd-logind

    # Custom Env Vars (Global / Miscellaneous)
    CRAWL_DIR = "${dataHome}/crawl/";
    # NLTK data dir (tokenizers/corpora) — XDG-compliant, under ~/.local/share
    NLTK_DATA = "${dataHome}/nltk_data";

    # LV2 plugin path: user plugins (~/.lv2: NAM neural amp modeler) + system dir
    LV2_PATH = "${homeDir}/.lv2:/run/current-system/sw/lib/lv2";

    # RAG answer model (rag-search --llm) and neural OCR (pic-ocr). Both use
    # abliterated models imported into ollama; the censored base tags are gone.
    # 16GB VRAM (RX 9070 XT): models <= ~9GB run fully on GPU, bigger ones spill.
    #   qwen3-vl-abliterated:8b  (8.0GB) — uncensored, fully on GPU, 25 tok/s (default)
    #   qwen3.8:27b              (17GB)  — kept for RU quality, spills to CPU
    # The huihui_ai abliterated 30B/35B MoE tags (18-23GB) were removed on
    # 2026-11-11: they spilled to CPU at ~0.1 tok/s on this card.
    # llama-swap (127.0.0.1:9292) is the fast path for interactive chat.
    # Per-run override: RAG_LLM_MODEL=<model> rag-search search --llm "..."
    RAG_LLM_MODEL = "qwen3-vl-abliterated:8b";
    PIC_OCR_NN_MODEL = "qwen3-vl-abliterated:8b";
    __GL_VRR_ALLOWED = "1";
    GRIM_DEFAULT_DIR = "${homeDir}/pic/shots";
    LIBSEAT_BACKEND = "logind";
    PASSWORD_STORE_DIR = "${dataHome}/pass";
    PASSWORD_STORE_ENABLE_EXTENSIONS_DEFAULT = "true";
    PYTHON_HISTORY = "${dataHome}/python/history";
    PULSE_COOKIE = "${configHome}/pulse/cookie";
    TERMINFO = "${dataHome}/terminfo";
    TERMINFO_DIRS = "${dataHome}/terminfo:/usr/share/terminfo";
    # WINEPREFIX is intentionally NOT set globally: a global WINEPREFIX overrides
    # yabridge's per-plugin prefix auto-detection (Windows VSTs live in the
    # vstplugins prefix) and makes them fail in GUI hosts with "The Wine host
    # process has exited unexpectedly". wineapps sets WINEPREFIX per app itself.
    XAUTHORITY = "$XDG_RUNTIME_DIR/Xauthority";
    XZ_DEFAULTS = "-T 0";
    ZDOTDIR = lib.mkForce "${configHome}/zsh";
    # glib for native non-Nix VSTs (u-he Diva et al.) loaded by REAPER/Renoise:
    # the .so ships against libgio/libgobject, which are not in the default
    # loader path on NixOS.
    LD_LIBRARY_PATH = lib.mkForce "${pkgs.glib.out}/lib";

    # XDG compliance (xdg-ninja fixes)
    ANDROID_AVD_HOME = "${dataHome}/android/avd";
    ANDROID_USER_HOME = "${dataHome}/android";
    BUN_INSTALL = "${dataHome}/bun"; # bun's global root (~/.bun otherwise)
    ELM_HOME = "${cacheHome}/elm"; # elm package cache (~/.elm otherwise)
    GNUPGHOME = "${dataHome}/gnupg";
    GTK2_RC_FILES = "${configHome}/gtk-2.0/gtkrc";
    IPYTHONDIR = "${configHome}/ipython"; # profiles + history (~/.ipython otherwise)
    KERAS_HOME = "${stateHome}/keras";
    NETHACKOPTIONS = "@${configHome}/nethack/config";
    NPM_CONFIG_CACHE = "${cacheHome}/npm";
    NPM_CONFIG_INIT_MODULE = "${configHome}/npm/config/npm-init.js";
    NPM_CONFIG_TMP = "$XDG_RUNTIME_DIR/npm";
    TEXMFVAR = "${cacheHome}/texlive/texmf-var";
    TRITON_HOME = "${cacheHome}/triton"; # triton/torch kernel cache (~/.triton otherwise)
    W3M_DIR = "${dataHome}/w3m";
  };

  # The same glib LD_LIBRARY_PATH for the systemd user manager: VST hosts
  # (Renoise, REAPER, …) launched from the graphical session inherit the user
  # manager env, and a foreign runtime import-environment can clobber
  # environment.variables. glib.out holds libgio/libgobject needed by native
  # u-he VSTs (Diva.64.so etc.).
  # NOTE: [Manager] has no `Environment=` key — systemd used to log
  # "Unknown key 'Environment' in section [Manager], ignoring" and the var never
  # reached any unit; `DefaultEnvironment=` is the real directive.
  systemd.user.settings.Manager.DefaultEnvironment = [
    "LD_LIBRARY_PATH=${pkgs.glib.out}/lib"
  ];

  # Activation script to ensure profile links (legacy support)
  system.activationScripts.negProfileLinks = lib.stringAfter [ "users" ] (
    builtins.readFile (
      pkgs.replaceVars ./envs/profile-links.sh {
        bashExe = lib.getExe' pkgs.bash "bash";
        runuserExe = lib.getExe' pkgs.util-linux "runuser";
      }
    )
  );
}
