#!/bin/bash

APP_NAME="Proton Drive"

is_running=$(osascript -e 'tell application "System Events" to (name of processes) contains "Proton Drive"' 2>/dev/null)

if [[ "$is_running" != "true" ]]; then
  echo "$(date): launching Proton Drive"
  open -a "$APP_NAME"
else
  echo "$(date): Proton Drive already running"
fi
