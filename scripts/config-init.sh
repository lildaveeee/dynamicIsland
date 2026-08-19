#!/bin/bash
# $1 = config dir, $2 = config file path
DIR="$1"
FILE="$2"
mkdir -p "$DIR"
if [ ! -f "$FILE" ]; then
    printf '%s' $'clickLeft   = music\nclickRight  = controlPanel\nclickMiddle = notifHistory\ndragDown      = appLauncher\ndragDownRight = screenTime\npillColor   = #000000\npillOpacity = 1\naccentColor = #ffffff\ntextColor   = #ffffff\nfontFamily  = \n\nnotch1 = [Date, Cava, Time]\nnotch2 = [Workspaces]\nnotch3 = [Timer]\n' > "$FILE"
fi
cat "$FILE"
