#!/bin/bash
wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '[0-9]+\.[0-9]+'
