#!/bin/bash
resolve_icon() {
  local name="$1"
  [ -z "$name" ] && return
  if [ "${name#/}" != "$name" ]; then [ -f "$name" ] && echo "$name"; return; fi
  local dirs="$HOME/.local/share/icons /usr/share/icons /usr/share/pixmaps"
  for size in 48 32 64 128 256 22 16; do
    for theme in hicolor Papirus Papirus-Dark breeze breeze-dark Adwaita; do
      for base in $dirs; do
        for ext in png svg xpm; do
          local c="$base/$theme/${size}x${size}/apps/${name}.${ext}"
          [ -f "$c" ] && { echo "$c"; return; }
        done
      done
    done
    for theme in hicolor Papirus breeze Adwaita; do
      for base in $dirs; do
        for ext in svg png; do
          local c="$base/$theme/scalable/apps/${name}.${ext}"
          [ -f "$c" ] && { echo "$c"; return; }
        done
      done
    done
  done
  for ext in png svg xpm; do
    local c="/usr/share/pixmaps/${name}.${ext}"
    [ -f "$c" ] && { echo "$c"; return; }
  done
  find /usr/share/icons /usr/share/pixmaps "$HOME/.local/share/icons" -type f \( -name "${name}.png" -o -name "${name}.svg" \) 2>/dev/null | head -1
}

find /usr/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null | sort -u |
while IFS= read -r f; do
  name=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
  exec=$(grep -m1 '^Exec=' "$f" | cut -d= -f2- | sed 's/ *%[uUfFdDnNickvm]//g' | xargs)
  nodisp=$(grep -m1 '^NoDisplay=' "$f" | cut -d= -f2-)
  hidden=$(grep -m1 '^Hidden=' "$f" | cut -d= -f2-)
  icon=$(grep -m1 '^Icon=' "$f" | cut -d= -f2-)
  [ "$nodisp" = 'true' ] && continue
  [ "$hidden" = 'true' ] && continue
  [ -z "$name" ] && continue
  [ -z "$exec" ] && continue
  did=$(basename "$f" .desktop)
  resolved=$(resolve_icon "$icon")
  [ -z "$resolved" ] && resolved="$icon"
  printf '%s\x1f%s\x1f%s\x1f%s\n' "$name" "$exec" "$did" "$resolved"
done | sort -t$'\x1f' -k1,1 -f
