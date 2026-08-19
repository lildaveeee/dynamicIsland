#!/bin/bash
f="$HOME/.local/share/quickshell/notif-history.ndjson"
[ -f "$f" ] && cat "$f" || true
