//! Help and usage texts of the ported scripts.
//!
//! The shell originals printed these by `sed`-ing their own comment header (the
//! header lines are part of the installed script), so the exact bytes live here.
//! They are byte-for-byte the output of the original commands; the parity
//! harness compares them against the scripts directly.

pub const PIC_NOTIFY_USAGE: &str = r##"pic-notify: screenshot notification bridge to quickshell ScreenshotToast.
Usage: pic-notify IMAGE
  Extracts dimensions, size, depth from PNG header (identify -ping, fast).
  Copies path to clipboard, writes JSON data + touches semaphore for quickshell.
  Falls back to notify-send when quickshell does not answer its IPC.


"##;

pub const CLIP_HELP: &str = r##"clip: clipboard helper (cliphist/clipcat + extras)
Usage:
  clip                       # open clipboard menu (cliphist/clipcat)
  clip pipe [-p|--paste] [-c|--command CMD] [--]
  clip youtube-dw-list       # pick video URL from history and download
  clip youtube-dw            # download URL currently in clipboard
  clip youtube-view          # open yt scratchpad and paste selection
  clip -h|--help|help        # this help
Env:
  USE_CLIPCAT=true           # use clipcat instead of cliphist
[ -z "${USE_CLIPCAT-}" ] && USE_CLIPCAT=false


IFS=' 	
'



POSIX sh: avoid alias; provide function instead
"##;

pub const PIC_OCR_HELP: &str = r##"pic-ocr: OCR an image and put the result into the clipboard.

Engines:
  tesseract (default)  — classic, fast, eng+rus
  nn / neural          — local vision model via Ollama (qwen3-vl:8b by
                         default, override with PIC_OCR_NN_MODEL). Images
                         never leave the machine.
  menu                 — pick an engine with vicinae dmenu

Usage:
  pic-ocr [IMAGE]                 # tesseract on IMAGE
  pic-ocr --engine=nn IMAGE       # neural OCR
  pic-ocr --menu IMAGE            # choose engine interactively
  pic-ocr                         # select a region with slurp first
  pic-ocr -h                      # help

Result: copied to clipboard (wl-copy) + notify-send preview.
Dependencies: tesseract, wl-copy, slurp, grim, notify-send, curl, jq, magick.
"##;

pub const PIC_DIRS_LIST_HELP: &str = r##"Usage: pic-dirs-list
"##;

pub const PIC_INFO_USAGE: &str = r##"Usage: pic-info [FILE...]
  Without arguments, inspects the newest file inside $PIC_INFO_DIR (or $GRIM_DEFAULT_DIR).
  For each file, forwards the preview request to pic-notify.
"##;

pub const PNGOPTIM_USAGE: &str = r##"Usage: pngoptim FILE.png
"##;
