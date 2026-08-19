#!/bin/bash
# $1 = connmanctl service ID
connmanctl disconnect "$1" 2>/dev/null
