#!/bin/bash
connmanctl scan wifi 2>/dev/null; sleep 1
connmanctl services 2>/dev/null | grep -E '^\s+[\*o ]' |
while read line; do
  NAME=$(echo "$line" | sed 's/^[[:space:]]*[\*o ]\?[[:space:]]*//' | sed 's/[[:space:]]*wifi_[a-f0-9_]*$//')
  SERVICE=$(echo "$line" | grep -oP 'wifi_[a-f0-9_]+')
  [ -z "$SERVICE" ] && continue
  CONNECTED=$(echo "$line" | grep -c '^[[:space:]]\*')
  INFO=$(connmanctl services "$SERVICE" 2>/dev/null)
  STRENGTH=$(echo "$INFO" | grep -oP 'Strength = \K[0-9]+' | head -1)
  SECURITY=$(echo "$INFO" | grep -oP 'Security = \[ \K[^\]]+' | head -1)
  [ -z "$STRENGTH" ] && STRENGTH=0
  [ -z "$SECURITY" ] && SECURITY=none
  [ -z "$NAME" ] && NAME="Hidden network"
  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\n' "$NAME" "$SERVICE" "$STRENGTH" "$SECURITY" "$CONNECTED"
done
