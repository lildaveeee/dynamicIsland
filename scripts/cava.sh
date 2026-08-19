#!/bin/bash
CONFIG=$(mktemp /tmp/cava-XXXXXX.conf)
printf '[general]\nbars=10\nsleep_timer=2\nsensitivity=200\nnoise_reduction=0.4\n[input]\nmethod=pulse\nsource=auto\n[output]\nmethod=raw\nraw_target=/dev/stdout\ndata_format=ascii\nascii_max_range=9\nbar_delimiter=59\nframe_delimiter=10\n' > "$CONFIG"
exec cava -p "$CONFIG"
