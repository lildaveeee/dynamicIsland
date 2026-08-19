#!/bin/bash
while true; do
  STATUS=$(mullvad status 2>/dev/null)
  if echo "$STATUS" | head -1 | grep -qi '^connected'; then
    LOCATION=$(echo "$STATUS" | grep -i 'Visible location:' | sed 's/.*Visible location:[[:space:]]*//' | sed 's/\. IPv4:.*//')
    if [ -n "$LOCATION" ]; then
      echo "connected · $LOCATION"
    else
      echo "connected"
    fi
  else
    echo "disconnected"
  fi
  sleep 3
done
