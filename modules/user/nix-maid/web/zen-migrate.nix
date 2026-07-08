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
in
{
  config = lib.mkIf webEnabled {
    environment.systemPackages = [
      pkgs.sqlite # SQLite database engine (for reading Zen/Firefox places.sqlite)
      zenBookmarksExport # Export Zen browser bookmarks to Netscape HTML for Vivaldi import
    ];
  };
}
