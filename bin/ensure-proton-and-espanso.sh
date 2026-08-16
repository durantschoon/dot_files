#!/bin/bash

PROTON_APP="Proton Drive"
ESPANSO_APP="Espanso"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

# Proton-backed Espanso config path.
#
# The CloudStorage mount is named ProtonDrive-<account address>-folder, so it
# is discovered by glob rather than hardcoded -- this repo is public and the
# account address does not belong in it. Override either of:
#
#   ESPANSO_CONFIG_PATH  full path to the espanso config dir
#   PROTON_DRIVE_DIR     the ProtonDrive-<account>-folder mount root
#
# (set them in ~/.shared.zshenv, which is not tracked here).
find_proton_dir() {
  local candidate
  for candidate in "$HOME"/Library/CloudStorage/ProtonDrive-*-folder; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ -z "${ESPANSO_CONFIG_PATH:-}" ]]; then
  PROTON_DRIVE_DIR="${PROTON_DRIVE_DIR:-$(find_proton_dir)}"
  # Empty if no mount was found; handled by the dir check below.
  ESPANSO_CONFIG_PATH="${PROTON_DRIVE_DIR:+$PROTON_DRIVE_DIR/espanso}"
fi
SENTINEL_FILE="${ESPANSO_CONFIG_PATH:+$ESPANSO_CONFIG_PATH/match/base.yml}"

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
if [[ -z "$ESPANSO_CONFIG_PATH" ]]; then
    log "No ProtonDrive-*-folder mount found (set PROTON_DRIVE_DIR to override)"
    exit 0
fi

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
    if [[ -z "$(head "$HOME/.espanso_config_link/match/base.yml" 2>/dev/null)" ]]; then
        log "Config link base.yml not ready yet"
    else
        log "Launching Espanso"
        open -a "$ESPANSO_APP"
    fi
else
    log "Espanso already running"
fi
