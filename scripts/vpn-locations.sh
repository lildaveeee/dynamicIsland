#!/bin/bash
# Outputs: country|countryCode|city|cityCode
# One line per city, parsed from `mullvad relay list`

mullvad relay list 2>/dev/null | awk '
/^\t[^\t]/ {
    # City line: "\tCity Name (code) @ ..."
    line = $0
    gsub(/^\t/, "", line)
    # Extract city name and code
    match(line, /^(.+) \(([a-z]+)\)/, arr)
    city = arr[1]
    cityCode = arr[2]
    print country "|" countryCode "|" city "|" cityCode
}
/^[^\t]/ {
    # Country line: "Country Name (code)"
    match($0, /^(.+) \(([a-z]+)\)/, arr)
    country = arr[1]
    countryCode = arr[2]
}
'
