#!/bin/bash
# Usage: vpn-location-set.sh <countryCode> <cityCode>
# e.g.   vpn-location-set.sh ch zrh
COUNTRY="$1"
CITY="$2"

if [ -z "$COUNTRY" ] || [ -z "$CITY" ]; then
    echo "Usage: $0 <countryCode> <cityCode>" >&2
    exit 1
fi

mullvad relay set location "$COUNTRY" "$CITY" 2>&1
# Reconnect if already connected
mullvad status 2>/dev/null | grep -qi '^connected' && mullvad reconnect 2>/dev/null
echo "done"
