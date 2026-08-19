#!/bin/bash
obs-cmd -w obsws://localhost:4455 recording status 2>/dev/null | grep -i 'active:' | grep -qi 'true' && echo 'recording' || echo 'stopped'
