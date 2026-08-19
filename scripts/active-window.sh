#!/bin/bash
while true; do
  hyprctl activewindow -j 2>/dev/null | grep -oP '"initialClass":\s*"\K[^"]+' | head -1 || echo ''
  sleep 2
done
