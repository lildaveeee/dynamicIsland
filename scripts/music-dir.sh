#!/bin/bash
for f in ~/.config/mpd/mpd.conf /etc/mpd.conf; do
  [ -f "$f" ] || continue
  D=$(grep -Po '(?<=music_directory ")[^"]+' "$f" 2>/dev/null | head -1)
  [ -z "$D" ] && D=$(grep -Po "(?<=music_directory ')[^']+" "$f" 2>/dev/null | head -1)
  [ -n "$D" ] && eval echo "$D" && exit 0
done
echo "$HOME/Music"
