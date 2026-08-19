#!/bin/bash
mkdir -p "$HOME/Pictures/Snips"
ts=$(date +%Y%m%d-%H%M%S)
grim -g "$(slurp)" "$HOME/Pictures/Snips/snip-$ts.png" && \
  wl-copy < "$HOME/Pictures/Snips/snip-$ts.png" && \
  notify-send 'Snip saved & copied' "$HOME/Pictures/Snips/snip-$ts.png" || \
  notify-send 'Snip cancelled'
