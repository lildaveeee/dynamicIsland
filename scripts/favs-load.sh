#!/bin/bash
# $1 = favs file path
f="$1"
[ -f "$f" ] && cat "$f" || true
