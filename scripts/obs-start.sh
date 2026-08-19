#!/bin/bash
pgrep -x obs > /dev/null || obs --minimize-to-tray &>/dev/null &
for i in $(seq 1 20); do
  obs-cmd -w obsws://localhost:4455 recording start 2>/dev/null && exit 0
  sleep 0.5
done
