#!/bin/bash
FIFO=/tmp/quickshell-notif.fifo
rm -f "$FIFO"; mkfifo "$FIFO"
DIR="$HOME/.config/dunst"; mkdir -p "$DIR"

cat > "$DIR/notify-hook.sh" << 'HOOKEOF'
#!/bin/bash
ICON="$DUNST_ICON_PATH"
# Resolve a bare icon name to a real file path.
# Strategy: prefer 48px PNG, then 32px, then any size, then SVG.
resolve_icon() {
  local name="$1"
  local dirs="$HOME/.local/share/icons /usr/share/icons /usr/share/pixmaps"
  # Try preferred sizes first: 48, 32, 64, 256, scalable
  for size in 48 32 64 128 256 22 16 scalable; do
    for base in $dirs; do
      for ext in png svg xpm; do
        local candidate
        # hicolor/<size>x<size>/apps/<name>.<ext>
        candidate="$base/hicolor/${size}x${size}/apps/${name}.${ext}"
        [ -f "$candidate" ] && { echo "$candidate"; return; }
        # Any theme that has the right size subfolder
        for theme in Papirus Papirus-Dark breeze breeze-dark Adwaita hicolor; do
          candidate="$base/$theme/${size}x${size}/apps/${name}.${ext}"
          [ -f "$candidate" ] && { echo "$candidate"; return; }
        done
      done
    done
    # scalable folder uses different naming
    for base in $dirs; do
      for theme in hicolor Papirus breeze Adwaita; do
        for ext in svg png; do
          local candidate="$base/$theme/scalable/apps/${name}.${ext}"
          [ -f "$candidate" ] && { echo "$candidate"; return; }
        done
      done
    done
  done
  # Broad fallback: find anywhere under icon dirs
  find $dirs /usr/share/pixmaps -type f \
    \( -name "${name}.png" -o -name "${name}.svg" \) \
    2>/dev/null | head -1
}
if [ -n "$ICON" ] && [ "${ICON#/}" = "$ICON" ]; then
  # Bare icon name — resolve it
  RESOLVED=$(resolve_icon "$ICON")
  if [ -z "$RESOLVED" ]; then
    # Try lowercase app name as icon name
    ALT=$(echo "$DUNST_APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    RESOLVED=$(resolve_icon "$ALT")
  fi
  [ -n "$RESOLVED" ] && ICON="$RESOLVED"
elif [ -z "$ICON" ] && [ -n "$DUNST_APP_NAME" ]; then
  # No icon at all — try to find one from the app name
  ALT=$(echo "$DUNST_APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  ICON=$(resolve_icon "$ALT")
fi
# Extract a URL from the notification body or summary.
# Priority: <a href="URL">, bare https://, bare http://
extract_url() {
  local text="$1"
  # href attribute in an anchor tag
  local u
  u=$(echo "$text" | grep -oP 'href=["'"'"']\K[^"'"'"']+' | head -1)
  [ -n "$u" ] && { echo "$u"; return; }
  # bare URL starting with https:// or http://
  u=$(echo "$text" | grep -oP 'https?://[^\s<>"'"'"']+' | head -1)
  [ -n "$u" ] && { echo "$u"; return; }
}
NOTIF_URL=$(printf '%s' "$DUNST_URLS" | head -1 | tr -d '\r')
[ -z "$NOTIF_URL" ] && NOTIF_URL=$(extract_url "$DUNST_BODY")
[ -z "$NOTIF_URL" ] && NOTIF_URL=$(extract_url "$DUNST_SUMMARY")
printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' "$DUNST_SUMMARY" "$DUNST_BODY" "$DUNST_APP_NAME" "$ICON" "$DUNST_DESKTOP_ENTRY" "$NOTIF_URL" > /tmp/quickshell-notif.fifo
HOOKEOF
chmod +x "$DIR/notify-hook.sh"

RC="$HOME/.config/dunst/dunstrc"
mkdir -p "$(dirname "$RC")"
[ ! -f "$RC" ] && cp /etc/dunst/dunstrc "$RC" 2>/dev/null || touch "$RC"
if ! grep -q 'notify-hook' "$RC"; then
  sed -i '/^\[global\]/a script = ~/.config/dunst/notify-hook.sh' "$RC"
fi
add_or_replace() {
  local key="$1" val="$2"
  if grep -qE "^\s*${key}\s*=" "$RC"; then
    sed -i "s|^\s*${key}\s*=.*|    ${key} = ${val}|" "$RC"
  else
    sed -i "/^\[global\]/a \    ${key} = ${val}" "$RC"
  fi
}
add_or_replace offset            '0x-2000'
add_or_replace transparency      '100'
add_or_replace width             '0'
add_or_replace height            '0'
add_or_replace always_run_script 'true'
dunstctl reload 2>/dev/null || true
dunstctl history-clear 2>/dev/null || true
exec tail -f "$FIFO"
