#!/bin/bash
awk '{printf "%d", $1*1000}' /proc/uptime
