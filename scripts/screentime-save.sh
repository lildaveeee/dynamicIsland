#!/bin/bash
# $1 = config dir, $2 = screentime file path
# Payload passed via SCREENTIME_PAYLOAD env var
mkdir -p "$1"
printf '%s' "$SCREENTIME_PAYLOAD" > "$2"
