#!/bin/bash
# $1 = config dir, $2 = favs file path
# Payload passed via FAVS_PAYLOAD env var
mkdir -p "$1"
printf '%s\n' "$FAVS_PAYLOAD" > "$2"
