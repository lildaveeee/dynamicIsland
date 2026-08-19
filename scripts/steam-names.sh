#!/bin/bash
# ── Steam ──────────────────────────────────────────────────────────────────────
STEAM_ROOTS="$HOME/.steam/steam $HOME/.local/share/Steam"
SEARCH_PATHS=""
for root in $STEAM_ROOTS; do
  vdf="$root/steamapps/libraryfolders.vdf"
  if [ -f "$vdf" ]; then
    while IFS= read -r line; do
      p=$(echo "$line" | grep -oP '"path"\s+"\K[^"]+')
      [ -n "$p" ] && SEARCH_PATHS="$SEARCH_PATHS $p/steamapps"
    done < "$vdf"
  fi
  [ -d "$root/steamapps" ] && SEARCH_PATHS="$SEARCH_PATHS $root/steamapps"
done

find $SEARCH_PATHS 2>/dev/null -maxdepth 1 -name 'appmanifest_*.acf' | sort -u |
while read f; do
  ID=$(basename "$f" .acf | sed 's/appmanifest_//')
  NAME=$(grep -oP '(?<="name")\s*"\K[^"]+' "$f" | head -1)
  case "$NAME" in
    steam_app_*|"") continue ;;  # skip Lutris/Heroic shim entries
  esac
  printf '%s|%s\n' "$ID" "$NAME"
done

# ── Lutris ─────────────────────────────────────────────────────────────────────
LUTRIS_DB="$HOME/.local/share/lutris/pga.db"
if [ -f "$LUTRIS_DB" ] && command -v sqlite3 &>/dev/null; then
  sqlite3 "$LUTRIS_DB" \
    "SELECT id, name FROM games WHERE name IS NOT NULL AND name != '' ORDER BY name;"
fi

# ── Heroic – Epic ──────────────────────────────────────────────────────────────
for lib in \
  "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/store_cache/legendary_library.json" \
  "$HOME/snap/heroic/current/.config/heroic/store_cache/legendary_library.json" \
  "$HOME/.config/heroic/store_cache/legendary_library.json"
do
  [ -f "$lib" ] || continue
  python3 - "$lib" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
library = data if isinstance(data, list) else data.get("library", [])
for g in library:
    name = g.get("title") or g.get("app_title") or ""
    aid  = g.get("app_name") or g.get("appName") or ""
    if name and aid:
        print(f"{aid}|{name}")
PY
  break
done

# ── Heroic – GOG ───────────────────────────────────────────────────────────────
for lib in \
  "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/store_cache/gog_library.json" \
  "$HOME/snap/heroic/current/.config/heroic/store_cache/gog_library.json" \
  "$HOME/.config/heroic/store_cache/gog_library.json"
do
  [ -f "$lib" ] || continue
  python3 - "$lib" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
library = data if isinstance(data, list) else data.get("games", [])
for g in library:
    name = g.get("title") or g.get("app_title") or ""
    aid  = str(g.get("id") or g.get("app_name") or "")
    if name and aid:
        print(f"{aid}|{name}")
PY
  break
done
