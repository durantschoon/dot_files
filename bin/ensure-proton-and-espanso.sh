#!/bin/bash

PROTON_APP="Proton Drive"
ESPANSO_APP="Espanso"

# Proton-backed Espanso config path
ESPANSO_CONFIG_PATH="$HOME/Library/CloudStorage/ProtonDrive-benjamin.schoon@protonmail.com-folder/espanso"
SENTINEL_FILE="$ESPANSO_CONFIG_PATH/match/base.yml"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

gui_app_running() {
  local app_name="$1"
  osascript -e "tell application \"System Events\" to (name of processes) contains \"$app_name\"" 2>/dev/null
}

if [[ "$(gui_app_running "$PROTON_APP")" != "true" ]]; then
  log "Launching Proton Drive"
  open -a "$PROTON_APP"
  exit 0
fi

# 1. Directory exists
if [[ ! -d "$ESPANSO_CONFIG_PATH" ]]; then
    log "Config dir not available yet"
    exit 0
fi

# 2. Directory readable
if [[ ! -r "$ESPANSO_CONFIG_PATH" ]]; then
    log "Config dir not readable yet"
    exit 0
fi

# 3. Sentinel file exists
if [[ ! -e "$SENTINEL_FILE" ]]; then
    log "Sentinel file not ready yet"
    exit 0
fi

# 4. Sentinel file readable
if [[ ! -r "$SENTINEL_FILE" ]]; then
    log "Sentinel file not readable yet"
    exit 0
fi

# 5. Ensure Espanso is running
if ! pgrep -x espanso >/dev/null 2>&1; then
    log "Launching Espanso"
    open -a "$ESPANSO_APP"
else
    log "Espanso already running"
fi
