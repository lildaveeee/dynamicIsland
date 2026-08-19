#!/bin/bash
mpc status 2>/dev/null | grep -oP '\[(playing|paused)\]' | tr -d '[]'
