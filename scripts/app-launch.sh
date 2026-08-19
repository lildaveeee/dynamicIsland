#!/bin/bash
# $1 = desktopId, $2 = exec string
gtk-launch "$1" 2>/dev/null || nohup sh -c "$2" &>/dev/null &
