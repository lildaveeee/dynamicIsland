#!/bin/bash
# $1 = "enable" or "disable"
if [ "$1" = "enable" ]; then
    rfkill unblock bluetooth
else
    rfkill block bluetooth
fi
