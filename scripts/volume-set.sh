#!/bin/bash
# $1 = volume percent (integer, e.g. 75)
wpctl set-volume @DEFAULT_AUDIO_SINK@ "$1%"
