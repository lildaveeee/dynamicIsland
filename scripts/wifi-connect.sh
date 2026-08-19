#!/bin/bash
# $1 = connmanctl service ID (e.g. wifi_aabbcc...)
connmanctl connect "$1" 2>&1 | tail -1
