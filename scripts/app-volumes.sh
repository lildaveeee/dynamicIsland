#!/bin/bash
wpctl status 2>/dev/null | sed -n '/Streams:/,/^[^ ]/p' | \
grep -E '^[[:space:]]+[0-9]+\.' | \
sed -E 's/^[[:space:]]*([0-9]+)\. (.*)$/\1|\2/' | \
while IFS='|' read -r ID NAME; do
  case "$NAME" in
    *pavucontrol*|*Pavucontrol*|*PulseAudio*|*pulseaudio*) continue;;
    *capture*|*Capture*|*record*|*Record*|*microphone*|*Microphone*) continue;;
  esac
  MEDIA_CLASS=$(pw-cli info "$ID" 2>/dev/null | grep 'media.class' | grep -o '"[^"]*"' | tail -1 | tr -d '"')
  case "$MEDIA_CLASS" in
    Stream/Output/Audio) ;;
    *) continue;;
  esac
  V=$(wpctl get-volume "$ID" 2>/dev/null | grep -oP '[0-9]+\.[0-9]+' | head -1)
  [ -n "$V" ] && printf '%s|%s|%s\n' "$ID" "$NAME" "$V"
done
