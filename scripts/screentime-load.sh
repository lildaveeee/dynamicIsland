#!/bin/bash
# Usage: screentime-load.sh <screentimeFile> <configDir>
SCREENTIME_FILE="$1"
CONFIG_DIR="$2"

if [ -f "$SCREENTIME_FILE" ]; then
  cat "$SCREENTIME_FILE"
  exit 0
fi

# Migration: merge old playtime.json + total-uptime.json into combined format
pf="$CONFIG_DIR/playtime.json"
uf="$CONFIG_DIR/total-uptime.json"
apps=$([ -f "$pf" ] && cat "$pf" || echo '{}')
ut=$([ -f "$uf" ] && cat "$uf" || echo '{"totalMs":0}')
python3 -c "import sys,json; a=json.loads(sys.argv[1]); u=json.loads(sys.argv[2]); print(json.dumps({'uptime':u,'apps':a}))" "$apps" "$ut" 2>/dev/null || echo '{}'
