#!/bin/bash
# $1 = PipeWire node ID, $2 = volume percent (integer)
wpctl set-volume "$1" "$2%"
