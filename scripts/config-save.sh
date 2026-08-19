#!/bin/bash
# $1 = config file path
# Content passed via _ISLAND_CFG env var
printf '%s' "$_ISLAND_CFG" > "$1"
