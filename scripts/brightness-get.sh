#!/bin/bash
B=$(brightnessctl get 2>/dev/null)
M=$(brightnessctl max 2>/dev/null)
[ -n "$B" ] && [ -n "$M" ] && echo "scale=4; $B / $M" | bc || echo '0.5'
