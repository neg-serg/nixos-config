# OCR tooling: scans and PDFs -> Markdown through llama.cpp vision models.
#
# Tesseract was removed on 2026-11-08, together with ocrmypdf (only a tesseract
# front end): on a scan benchmark with Russian text, a table and a formula it
# lost 7 of 14 key fields (Н·м, −12,5, ±, superscripts) and produced garbage
# for the math, while the local Qwen3-VL-8B read 14/14 at 0.65% CER and
# PaddleOCR-VL 12/14 in 2 s. `pic-ocr` is neural-only now (packages/
# local-bin-desktop); this module keeps the docling launcher and `ocr`.
#
# Docling (PDF/DOCX → Markdown, layout + table models) stays out of the system
# closure: its python env is ~3.9 GiB. The `docling` launcher below builds the
# flake attr `docling-env` on first use and GC-roots it under $HOME; `nix run
# .#docling -- file.pdf` and the `ai` devshell reach the same env; pdf2md
# (packages/local-bin-system) resolves `docling` from PATH.
#
# The first conversion downloads ~500 MiB of layout/table models into
# ~/.cache/huggingface; later runs are offline.
#
# `ocr` (below) is the nudge-free path for scans and screenshots: it sends an
# image, or every page of a PDF rendered with pdftoppm, to the llama-swap
# `ocr` slot (PaddleOCR-VL-1.6) and prints Markdown. It needs neither the
# docling env nor any OCR engine at run time.
{ pkgs, config, ... }:
let
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  environment.systemPackages = [
    (onDemand {
      name = "docling";
      attr = "docling-env";
    }) # PDF/DOCX → Markdown with layout/table models, built on first use
    (pkgs.writeShellApplication {
      name = "ocr";
      runtimeInputs = [
        pkgs.curl # HTTP request to the llama-swap endpoint
        pkgs.jq # JSON body assembly and response extraction
        pkgs.coreutils # base64, mktemp, sort
        pkgs."poppler-utils" # pdftoppm: PDF pages to PNG
      ];
      text = ''
        # Documents and scans to Markdown through the llama-swap `ocr` slot
        # (PaddleOCR-VL-1.6, modules/llm/llama-swap.nix). PDFs are rendered
        # page by page with pdftoppm; the prompt selects the task, as the
        # model card prescribes.
        url="''${OCR_URL:-http://127.0.0.1:9292/v1/chat/completions}"
        model="''${OCR_MODEL:-ocr}"
        prompt="OCR:"
        out=""
        files=()
        usage() {
          echo "usage: ocr [--table|--formula|--chart|--seal] [-o out.md] FILE..." >&2
        }
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --table) prompt="Table Recognition:"; shift ;;
            --formula) prompt="Formula Recognition:"; shift ;;
            --chart) prompt="Chart Recognition:"; shift ;;
            --seal) prompt="Seal Recognition:"; shift ;;
            -o | --output) out="''${2:?--output needs a path}"; shift 2 ;;
            -h | --help) usage; exit 0 ;;
            -*) echo "unknown option: $1" >&2; usage; exit 2 ;;
            *)
              files+=("$1")
              shift
              ;;
          esac
        done
        [ "''${#files[@]}" -gt 0 ] || {
          usage
          exit 2
        }

        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT

        mime() {
          case "''${1##*.}" in
            jpg | jpeg | JPG | JPEG) echo image/jpeg ;;
            webp | WEBP) echo image/webp ;;
            gif | GIF) echo image/gif ;;
            *) echo image/png ;;
          esac
        }

        ocr_image() {
          local image="$1" b64file bodyfile
          # A rendered page is megabytes; argv has a limit, so base64 goes
          # through a file and jq reads it with --rawfile.
          b64file="$tmp/$(basename "$image").b64"
          base64 -w0 "$image" > "$b64file"
          bodyfile="$b64file.json"
          jq -n \
            --rawfile img "$b64file" \
            --arg mime "$(mime "$image")" \
            --arg model "$model" \
            --arg prompt "$prompt" \
            '{model: $model, max_tokens: 4096, temperature: 0,
              messages: [{role: "user", content: [
                {type: "image_url", image_url: {url: ("data:" + $mime + ";base64," + $img)}},
                {type: "text", text: $prompt}]}]}' > "$bodyfile"
          curl -sS --max-time 600 "$url" -H 'Content-Type: application/json' \
            --data-binary @"$bodyfile" |
            jq -er '.choices[0].message.content // ("ERROR: " + (.error.message // "no response"))'
        }

        for file in "''${files[@]}"; do
          case "''${file,,}" in
            *.pdf)
              dir="$tmp/$(basename "''${file%.*}")"
              mkdir -p "$dir"
              pdftoppm -r 200 -png "$file" "$dir/page"
              while IFS= read -r page; do
                echo "## page $(basename "$page" .png | sed 's/^page-//')"
                ocr_image "$page"
                echo
              done < <(printf '%s\n' "$dir"/page-*.png | sort -V)
              ;;
            *)
              ocr_image "$file"
              echo
              ;;
          esac
        done > "''${out:-/dev/stdout}"
      '';
    }) # documents/scans → Markdown via the PaddleOCR-VL slot, on demand
  ];
}
