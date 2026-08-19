#!/bin/bash
hyprctl dispatch dpms off && loginctl suspend 2>/dev/null || zzz
