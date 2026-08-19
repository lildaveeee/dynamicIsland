#!/bin/bash
# $1 = "enable" or "disable"
if [ "$1" = "enable" ]; then
    connmanctl enable wifi && connmanctl enable ethernet
else
    connmanctl disable wifi && connmanctl disable ethernet
fi
