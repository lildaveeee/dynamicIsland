#!/bin/bash
for base in \
  "$HOME/.local/share/Steam/appcache/librarycache" \
  "$HOME/.steam/steam/appcache/librarycache" \
  "$HOME/.local/share/Steam/steam/games" \
  "$HOME/.steam/steam/steam/games"; do
  [ -d "$base" ] || continue
  find "$base" -maxdepth 1 -type f \
    \( -name '*_icon.jpg' -o -name '*_icon.png' -o -name '*.ico' \) \
    -print 2>/dev/null
done
