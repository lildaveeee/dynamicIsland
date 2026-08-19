#!/bin/bash
# CPU: two /proc/stat samples 400ms apart for an accurate delta
read -r _ u n s i _ < /proc/stat
sleep 0.4
read -r _ u2 n2 s2 i2 _ < /proc/stat
total=$(( (u2 + n2 + s2 + i2) - (u + n + s + i) ))
idle=$(( i2 - i ))
[ "$total" -gt 0 ] && cpu=$(( (total - idle) * 100 / total )) || cpu=0

# RAM: used = total - free - buffers - cached  (actual application pressure)
mem_total=$(awk '/^MemTotal:/{print $2}'   /proc/meminfo)
mem_free=$(awk  '/^MemFree:/{print $2}'    /proc/meminfo)
mem_buf=$(awk   '/^Buffers:/{print $2}'    /proc/meminfo)
mem_cache=$(awk '/^Cached:/{print $2}'     /proc/meminfo)
mem_used=$(( mem_total - mem_free - mem_buf - mem_cache ))
[ "$mem_total" -gt 0 ] && ram=$(( mem_used * 100 / mem_total )) || ram=0

# GPU: nvidia-smi (robust) → any AMD card → 0
gpu=0
if command -v nvidia-smi &>/dev/null; then
    raw=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' \t')
    # nvidia-smi can return "[Not Supported]" or empty when GPU is idle/suspended
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        gpu=$raw
    fi
else
    # Search all DRM cards for AMD gpu_busy_percent
    for card in /sys/class/drm/card*/device/gpu_busy_percent; do
        [ -f "$card" ] || continue
        val=$(cat "$card" 2>/dev/null)
        if [[ "$val" =~ ^[0-9]+$ ]]; then
            gpu=$val
            break
        fi
    done
fi

echo "$cpu|$ram|$gpu"
