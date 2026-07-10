{
  pkgs,
  lib,
  config,
  ...
}:
let
  webEnabled = config.features.web.enable or false;

  zenBookmarksExport = (pkgs.writeShellApplication {
    name = "zen-bookmarks-export";
    runtimeInputs = with pkgs; [ sqlite ];
    text = ''
      # Zen → Vivaldi: export Firefox-format bookmarks to Netscape HTML
      # Uses recursive CTE on moz_bookmarks to preserve folder hierarchy

      set -euo pipefail

      PROFILE=""

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --profile)
            if [ -z "''${2-}" ]; then
              echo "Error: --profile requires a path argument" >&2
              exit 1
            fi
            PROFILE="$2"
            shift 2
            ;;
          --help|-h)
            cat <<'HELP'
Usage: zen-bookmarks-export [--profile PATH]

Exports Zen browser bookmarks to Netscape HTML format for Vivaldi import.

Options:
  --profile PATH  Explicit path to a Zen profile directory containing places.sqlite
  --help, -h      Show this help message

If --profile is omitted, searches ~/.zen/*/ and ~/.config/zen/*/ for places.sqlite
and uses the profile with the most recently modified database.
HELP
            exit 0
            ;;
          *)
            echo "Error: Unknown option: $1" >&2
            echo "Usage: zen-bookmarks-export [--profile PATH]" >&2
            exit 1
            ;;
        esac
      done

      # ---- Resolve profile directory ----
      if [ -n "$PROFILE" ]; then
        PROFILE_DIR="$PROFILE"
      else
        SEARCH_DIRS=()
        [ -d "$HOME/.zen" ] && SEARCH_DIRS+=("$HOME/.zen")
        [ -d "$HOME/.config/zen" ] && SEARCH_DIRS+=("$HOME/.config/zen")

        PROFILES=()
        for base in "''${SEARCH_DIRS[@]}"; do
          while IFS= read -r -d $'\0' d; do
            PROFILES+=("$d")
          done < <(find "$base" -maxdepth 2 -name 'places.sqlite' -printf '%h\0' 2>/dev/null || true)
        done

        if [ "''${#PROFILES[@]}" -eq 0 ]; then
          echo "Error: No Zen profile found with places.sqlite" >&2
          echo "Searched: ~/.zen/*/ and ~/.config/zen/*/" >&2
          exit 1
        fi

        BEST=""
        BEST_TIME=0
        for p in "''${PROFILES[@]}"; do
          MTIME=$(stat -c '%Y' "$p/places.sqlite" 2>/dev/null || echo 0)
          if [ "$MTIME" -gt "$BEST_TIME" ]; then
            BEST_TIME=$MTIME
            BEST="$p"
          fi
        done
        PROFILE_DIR="$BEST"
      fi

      PLACES_DB="$PROFILE_DIR/places.sqlite"

      if [ ! -f "$PLACES_DB" ]; then
        echo "Error: places.sqlite not found at: $PLACES_DB" >&2
        exit 1
      fi

      echo "Using profile: $PROFILE_DIR"

      # ---- Verify database is readable ----
      BOOKMARK_COUNT=$(sqlite3 "$PLACES_DB" "SELECT COUNT(*) FROM moz_bookmarks WHERE type = 1;" 2>/dev/null || echo "ERROR")

      if [ "$BOOKMARK_COUNT" = "ERROR" ]; then
        echo "Error: Cannot read places.sqlite — file may be corrupt or invalid" >&2
        exit 1
      fi

      if [ "$BOOKMARK_COUNT" -eq 0 ]; then
        echo "Warning: No bookmarks found in this profile (exporting empty file)" >&2
      fi

      # ---- HTML escape function ----
      # Replaces & < > " with their HTML entities
      escape_html() {
        local s="$1"
        s="''${s//&/&amp;}"
        s="''${s//</&lt;}"
        s="''${s//>/&gt;}"
        s="''${s//\"/&quot;}"
        printf '%s' "$s"
      }

      # ---- Extract bookmark tree from SQLite ----
      OUTPUT_FILE="$HOME/zen-bookmarks-$(date +%Y-%m-%d).html"
      TMP_DATA=$(mktemp)
      trap 'rm -f "$TMP_DATA"' EXIT

      # Recursive CTE: start from known root folders (type=2),
      # traverse children (type=1=bookmark, type=2=folder),
      # produce a flat ordered list with depth tracking.
      sqlite3 -separator '|' "$PLACES_DB" "
        WITH RECURSIVE
        roots(id, label, idx) AS (
          SELECT b.id,
                 CASE b.id
                   WHEN 2 THEN 'Bookmarks Menu'
                   WHEN 3 THEN 'Bookmarks Toolbar'
                   WHEN 5 THEN 'Other Bookmarks'
                   WHEN 6 THEN 'Mobile Bookmarks'
                 END,
                 CASE b.id
                   WHEN 2 THEN 1
                   WHEN 3 THEN 2
                   WHEN 5 THEN 3
                   WHEN 6 THEN 4
                 END
          FROM moz_bookmarks b
          WHERE b.id IN (2, 3, 5, 6)
        ),
        tree(type, depth, title, url, add_date, sort_key, node_id) AS (
          SELECT
            2, 0, r.label,
            ''', COALESCE(b.dateAdded, 0) / 1000000,
            SUBSTR('0000' || CAST(r.idx AS TEXT), -4),
            b.id
          FROM roots r
          JOIN moz_bookmarks b ON b.id = r.id

          UNION ALL

          SELECT
            b.type,
            t.depth + 1,
            COALESCE(NULLIF(b.title, '''), '''),
            COALESCE(p.url, '''),
            COALESCE(b.dateAdded, 0) / 1000000,
            t.sort_key || '/' || SUBSTR('0000000000' || CAST(b.id AS TEXT), -10),
            b.id
          FROM moz_bookmarks b
          LEFT JOIN moz_places p ON b.fk = p.id
          JOIN tree t ON b.parent = t.node_id
          WHERE b.type IN (1, 2)
        )
        SELECT type, depth, title, url, add_date
        FROM tree
        ORDER BY sort_key ASC;
      " > "$TMP_DATA"

      # ---- Generate Netscape Bookmark HTML ----
      {
        echo '<!DOCTYPE NETSCAPE-Bookmark-file-1>'
        echo '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">'
        echo '<TITLE>Bookmarks</TITLE>'
        echo '<H1>Bookmarks</H1>'
        echo '<DL><p>'

        # dl_depth tracks how many <DL> tags are currently open.
        # Initial value 1 accounts for the outer <DL><p> above.
        dl_depth=1

        while IFS='|' read -r item_type depth title url add_date; do
          # Close <DL> tags until we reach the correct nesting level for this node.
          # A node at tree depth D needs dl_depth = D + 1 (the +1 for outer <DL>).
          while [ "$dl_depth" -gt "$((depth + 1))" ]; do
            echo '</DL><p>'
            dl_depth=$((dl_depth - 1))
          done

          if [ "$item_type" = "2" ]; then
            # Folder
            escaped_title=$(escape_html "$title")
            echo "<DT><H3 ADD_DATE=\"$add_date\">$escaped_title</H3>"
            echo '<DL><p>'
            dl_depth=$((dl_depth + 1))
          else
            # Bookmark (type=1)
            escaped_title=$(escape_html "$title")
            echo "<DT><A HREF=\"$url\" ADD_DATE=\"$add_date\">$escaped_title</A>"
          fi
        done < "$TMP_DATA"

        # Close all remaining open <DL> tags
        while [ "$dl_depth" -gt 0 ]; do
          echo '</DL><p>'
          dl_depth=$((dl_depth - 1))
        done
      } > "$OUTPUT_FILE"

      # ---- Summary ----
      BOOKMARK_COUNT=$(sqlite3 "$PLACES_DB" "SELECT COUNT(*) FROM moz_bookmarks WHERE type = 1;" 2>/dev/null || echo 0)
      FOLDER_COUNT=$(sqlite3 "$PLACES_DB" "SELECT COUNT(*) FROM moz_bookmarks WHERE type = 2 AND parent IS NOT NULL;" 2>/dev/null || echo 0)
      echo ""
      echo "Exported $BOOKMARK_COUNT bookmarks in $FOLDER_COUNT folders"
      echo ""
      echo "Output: $OUTPUT_FILE"
      echo ""
      echo "To import into Vivaldi:"
      echo "  1. Open vivaldi://bookmarks"
      echo "  2. Click 'Import' → 'Bookmarks HTML File'"
      echo "  3. Select: $OUTPUT_FILE"
      echo ""
      echo "Done."
    '';
  }).overrideAttrs (old: {
    pname = "zen-bookmarks-export";
    name = "zen-bookmarks-export";
  });

  # Python cookie pipeline scripts (read → decrypt → write)
  zenCookieRead = pkgs.writeTextFile {
    name = "zen-cookie-read";
    executable = true;
    destination = "/bin/zen-cookie-read";
    text = builtins.readFile ./zen-cookie-read.py;
  };

  zenCookieDecrypt = pkgs.writeTextFile {
    name = "zen-cookie-decrypt";
    executable = true;
    destination = "/bin/zen-cookie-decrypt";
    text = builtins.readFile ./zen-cookie-decrypt.py;
  };

  zenCookieWrite = pkgs.writeTextFile {
    name = "zen-cookie-write";
    executable = true;
    destination = "/bin/zen-cookie-write";
    text = builtins.readFile ./zen-cookie-write.py;
  };

  # CDP-based cookie writer: uses Vivaldi's Chrome DevTools Protocol instead of
  # direct SQLite writes. Vivaldi handles OSCrypt encryption internally.
  zenCookieCdpWrite = pkgs.writeShellApplication {
    name = "zen-cookie-cdp-write";
    runtimeInputs = with pkgs; [ (python3.withPackages (ps: [ ps.websocket-client ])) xvfb-run ];
    text = ''
      exec python3 "${./zen-cookie-cdp-write.py}" "$@"
    '';
  };

  # Orchestrator: migrates cookies from Zen to Vivaldi as a single step
  zenProfileMigrate = (pkgs.writeShellApplication {
    name = "zen-profile-migrate";
    runtimeInputs = with pkgs; [ sqlite (python3.withPackages (ps: [ ps.cryptography ps.websocket-client ])) nss procps coreutils findutils gnugrep gnused gnutar zenCookieRead zenCookieDecrypt zenCookieWrite zenCookieCdpWrite libsecret ];
    text = ''
      # zen-profile-migrate — Orchestrate Zen → Vivaldi profile migration
      # Part of nix-maid web migration suite

      set -euo pipefail

      export LD_LIBRARY_PATH="${pkgs.nss}/lib''${LD_LIBRARY_PATH:+:}''${LD_LIBRARY_PATH-}"

      # ── State ─────────────────────────────────────────────────────────────────
      ZEN_PROFILE=""
      YES=0
      DRY_RUN=0

      # Temp file for cookie JSON (cleaned up on exit)
      COOKIE_TMP=""
      cleanup() {
        [ -n "$COOKIE_TMP" ] && [ -f "$COOKIE_TMP" ] && rm -f "$COOKIE_TMP"
      }
      trap cleanup EXIT

      # ── Help ──────────────────────────────────────────────────────────────────
      show_help() {
        cat <<'HELP'
    Usage: zen-profile-migrate [OPTIONS]

    Orchestrate migration of Zen browser profile data to Vivaldi.
    Migrates bookmarks and cookies from the most recently used Zen profile
    to the Vivaldi Default profile.

    Options:
      --profile PATH  Explicit path to Zen profile directory (skip auto-detection)
      --yes           Skip confirmation prompt (required for non-interactive use)
      --dry-run       Print planned actions without writing anything
      --help, -h      Show this help message and exit

    Examples:
      zen-profile-migrate --dry-run
      zen-profile-migrate --yes
      zen-profile-migrate --profile ~/.zen/abc123.default/ --yes
    HELP
        exit 0
      }

      # ── Flag parsing ──────────────────────────────────────────────────────────
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --profile)
            if [ -z "''${2-}" ]; then
              echo "Error: --profile requires a path argument" >&2
              exit 1
            fi
            ZEN_PROFILE="$2"
            shift 2
            ;;
          --yes)
            YES=1
            shift
            ;;
          --dry-run)
            DRY_RUN=1
            shift
            ;;
          --help|-h)
            show_help
            ;;
          *)
            echo "Error: Unknown option: $1" >&2
            echo "Usage: zen-profile-migrate [OPTIONS]" >&2
            echo "Try 'zen-profile-migrate --help' for more information." >&2
            exit 1
            ;;
        esac
      done

      # ── Confirmation guard ────────────────────────────────────────────────────
      # --dry-run and --help are self-confirming; real migration requires --yes.
      if [ "$YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
        echo "Error: Use --yes to confirm migration" >&2
        exit 2
      fi

      # ══════════════════════════════════════════════════════════════════════════
      # STEP 1 — Check Zen is not running
      # ══════════════════════════════════════════════════════════════════════════
      echo "→ Checking Zen browser..."

      ZEN_RUNNING=0
      for bin in zen zen-browser firefox firefox-bin; do
        if pgrep -x "$bin" >/dev/null 2>&1; then
          ZEN_RUNNING=1
          break
        fi
      done

      if [ "$ZEN_RUNNING" -eq 1 ]; then
        echo "Error: Zen browser is running. Close it first." >&2
        exit 1
      fi
      echo "  ✓ Zen is not running"

      # ══════════════════════════════════════════════════════════════════════════
      # STEP 2 — Resolve Zen profile
      # ══════════════════════════════════════════════════════════════════════════
      echo "→ Resolving Zen profile..."

      if [ -n "$ZEN_PROFILE" ]; then
        PROFILE_DIR="$ZEN_PROFILE"
        if [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
          echo "Error: places.sqlite not found at: $PROFILE_DIR/places.sqlite" >&2
          exit 1
        fi
        echo "  Using explicit profile: $PROFILE_DIR"
      else
        SEARCH_DIRS=()
        [ -d "$HOME/.zen" ]           && SEARCH_DIRS+=("$HOME/.zen")
        [ -d "$HOME/.config/zen" ]    && SEARCH_DIRS+=("$HOME/.config/zen")

        if [ "''${#SEARCH_DIRS[@]}" -eq 0 ]; then
          echo "Error: No Zen profile directories found" >&2
          exit 1
        fi

        PROFILES=()
        for base in "''${SEARCH_DIRS[@]}"; do
          while IFS= read -r -d $'\0' d; do
            PROFILES+=("$d")
          done < <(find "$base" -maxdepth 2 -name 'places.sqlite' -printf '%h\0' 2>/dev/null || true)
        done

        if [ "''${#PROFILES[@]}" -eq 0 ]; then
          echo "Error: No Zen profile found with places.sqlite" >&2
          exit 1
        fi

        BEST=""; BEST_TIME=0
        for p in "''${PROFILES[@]}"; do
          MTIME=$(stat -c '%Y' "$p/places.sqlite" 2>/dev/null || echo 0)
          if [ "$MTIME" -gt "$BEST_TIME" ]; then
            BEST_TIME="$MTIME"
            BEST="$p"
          fi
        done
        PROFILE_DIR="$BEST"
        echo "  Detected profile: $PROFILE_DIR (most recently used)"
      fi

      # ══════════════════════════════════════════════════════════════════════════
      # STEP 3 — Check Vivaldi is not running
      # ══════════════════════════════════════════════════════════════════════════
      echo "→ Checking Vivaldi browser..."
      if pgrep -f vivaldi >/dev/null 2>&1; then
        echo "Error: Vivaldi is running. Close it first." >&2
        exit 1
      fi
      echo "  ✓ Vivaldi is not running"

      # ══════════════════════════════════════════════════════════════════════════
      # STEP 4 — Backup Vivaldi profile
      # ══════════════════════════════════════════════════════════════════════════
      BACKUP_PATH=""

      if [ "$DRY_RUN" -eq 0 ]; then
        if [ -d "$HOME/.config/vivaldi/Default" ]; then
          echo "→ Backing up Vivaldi Default profile..."
          BACKUP_PATH="$HOME/zen-to-vivaldi-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
          tar czf "$BACKUP_PATH" \
            --exclude='Cache' \
            --exclude='Code Cache' \
            --exclude='GPUCache' \
            --exclude='DawnCache' \
            --exclude='*.wal' \
            --exclude='*.shm' \
            -C "$HOME/.config/vivaldi/Default" .
          echo "  ✓ Backup created: $BACKUP_PATH"
        else
          echo "  → Vivaldi profile does not exist yet; backup skipped"
        fi
      else
        echo "  → Backup skipped (dry-run)"
      fi

      # ══════════════════════════════════════════════════════════════════════════
      # STEP 5 — Export bookmarks
      # ══════════════════════════════════════════════════════════════════════════
      echo "→ Exporting bookmarks..."

      BOOKMARK_OUTPUT="$HOME/zen-bookmarks-$(date +%Y-%m-%d).html"

      if [ "$DRY_RUN" -eq 0 ]; then
        zen-bookmarks-export --profile "$PROFILE_DIR"
        BOOKMARK_COUNT=$(sqlite3 "$PROFILE_DIR/places.sqlite" \
          "SELECT COUNT(*) FROM moz_bookmarks WHERE type = 1;" 2>/dev/null || echo 0)
        echo "  ✓ $BOOKMARK_COUNT bookmarks exported → $BOOKMARK_OUTPUT"
      else
        BOOKMARK_COUNT=$(sqlite3 "$PROFILE_DIR/places.sqlite" \
          "SELECT COUNT(*) FROM moz_bookmarks WHERE type = 1;" 2>/dev/null || echo 0)
        echo "  → $BOOKMARK_COUNT bookmarks would be exported (dry-run, file not written)"
      fi

      # ══════════════════════════════════════════════════════════════════════════
      # STEP 6 — Cookie migration pipeline
      # ══════════════════════════════════════════════════════════════════════════
      echo "→ Processing cookies..."

      COOKIE_TMP=$(mktemp)

      zen-cookie-read --profile "$PROFILE_DIR" > "$COOKIE_TMP"

      COOKIE_TOTAL=$(python3 -c "import json,sys; data=json.load(open('$COOKIE_TMP')); print(len(data))")

      COOKIE_PLAINTEXT=$(python3 -c "import json,sys; data=json.load(open('$COOKIE_TMP')); print(sum(1 for c in data if not c.get('needs_decryption')))")

      COOKIE_DECRYPTED=$(python3 -c "import json,sys; data=json.load(open('$COOKIE_TMP')); print(sum(1 for c in data if c.get('needs_decryption')))")

      echo "  Cookies read: $COOKIE_TOTAL total ($COOKIE_PLAINTEXT plaintext, $COOKIE_DECRYPTED encrypted)"

      if [ "$DRY_RUN" -eq 0 ]; then
        echo "→ Decrypting and writing cookies to Vivaldi..."
        zen-cookie-decrypt --profile "$PROFILE_DIR" < "$COOKIE_TMP" | zen-cookie-write --profile "$HOME/.config/vivaldi/Default"
        echo "  ✓ Cookies written to Vivaldi profile"
      else
        echo "  → Cookie decrypt/write skipped (dry-run)"
      fi

      # ══════════════════════════════════════════════════════════════════════════
      # STEP 7 — Post-migration report
      # ══════════════════════════════════════════════════════════════════════════
      echo ""
      echo "============================================================"
      if [ "$DRY_RUN" -eq 1 ]; then
        echo " DRY RUN — no changes were made"
      fi
      echo " ZEN → VIVALDI PROFILE MIGRATION REPORT"
      echo "============================================================"
      echo " Zen profile:         $PROFILE_DIR (left untouched)"
      echo " Vivaldi profile:     ~/.config/vivaldi/Default"
      if [ -n "$BACKUP_PATH" ]; then
        echo " Backup:              $BACKUP_PATH"
      else
        echo " Backup:              (none — profile did not exist or dry-run)"
      fi
      echo ""
      echo " Bookmarks exported:  $BOOKMARK_COUNT bookmarks → $BOOKMARK_OUTPUT"
      echo " Cookies migrated:    $COOKIE_TOTAL total ($COOKIE_PLAINTEXT plaintext, $COOKIE_DECRYPTED NSS-decrypted)"
      echo ""
      if [ -n "$BACKUP_PATH" ]; then
        echo " RESTORE BACKUP: tar xzf $BACKUP_PATH -C \"\$HOME/.config/vivaldi/\""
        echo ""
      fi
      echo " MANUAL STEPS:"
      echo "  1. Passwords: Export from Zen: about:logins → 'Export Logins...' → CSV"
      echo "     Import to Vivaldi: vivaldi --enable-features=PasswordImport"
      echo "     then vivaldi://password-manager/settings → Import"
      echo "  2. History & Autofill: vivaldi://settings/importData → select Firefox"
      echo "  3. Extensions: Reinstall from Chrome Web Store"
      echo "============================================================"
    '';
  });
in
{
  config = lib.mkIf webEnabled {
    environment.systemPackages = [
      pkgs.sqlite # SQLite database engine (for reading Zen/Firefox places.sqlite)
      zenBookmarksExport # Export Zen browser bookmarks to Netscape HTML for Vivaldi import
      zenProfileMigrate # Orchestrate Zen → Vivaldi profile migration (bookmarks + cookies)
      zenCookieRead # Read cookies from Firefox/Zen cookies.sqlite as JSON
      zenCookieDecrypt # Decrypt NSS-encrypted cookies via libnss3
      zenCookieWrite # Write decrypted cookies to Chromium/Vivaldi Cookies DB (direct SQLite)
      zenCookieCdpWrite # Write decrypted cookies to Vivaldi via Chrome DevTools Protocol (CDP)
    ];
  };
}
