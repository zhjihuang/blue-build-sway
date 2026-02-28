#!/usr/bin/bash

STATE=""

if [[ "$1" == "battery" || "$1" == "ac" ]]; then
  STATE="$1"
fi

if [[ $STATE == "" ]]; then
  if [[ $(cat /sys/class/power_supply/ADP1/online) == '1' ]]; then
    STATE="ac"
  else STATE="battery"
  fi
fi

echo $STATE

if [[ $STATE == "battery" ]]; then
  echo "Discharging, set governor to powersave"
  cpupower frequency-set -g powersave
elif [[ $STATE == "ac"  ]]; then
  echo "AC plugged in, set governor to performance"
  cpupower frequency-set -g performance
fi
