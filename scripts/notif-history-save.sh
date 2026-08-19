#!/bin/bash
# Payload passed via NOTIF_HISTORY_PAYLOAD env var
mkdir -p "$HOME/.local/share/quickshell"
printf '%s' "$NOTIF_HISTORY_PAYLOAD" > "$HOME/.local/share/quickshell/notif-history.ndjson"
