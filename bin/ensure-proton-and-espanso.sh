#!/bin/bash

PROTON_APP="Proton Drive"
ESPANSO_APP="Espanso"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

# Force-hydrate a possibly-dataless Proton Drive file and echo its contents.
#
# Proton Drive (like iCloud) can leave a synced file as a metadata-only
# placeholder whose reads return empty until the FileProvider downloads it on
# demand. Reading the file is what triggers materialization, so retry a few
# times to give the download a chance to complete before giving up. Returns
# non-zero (and echoes nothing) if the file is still empty after retries.
read_hydrated() {
    local file="$1" content i
    for i in 1 2 3 4 5; do
        content="$(cat "$file" 2>/dev/null)"
        if [[ -n "$content" ]]; then
            printf '%s' "$content"
            return 0
        fi
        sleep 2
    done
    return 1
}

# Lightweight YAML sanity check. Prints nothing and returns 0 when the file
# parses cleanly; prints the parser's error and returns non-zero otherwise.
# Uses the system Ruby, which is always present and independent of the user's
# PATH (important under launchd); passes silently if no parser is available.
validate_yaml() {
    local file="$1"
    if [[ -x /usr/bin/ruby ]]; then
        /usr/bin/ruby -ryaml -e 'begin; YAML.load_file(ARGV[0]); rescue => e; STDERR.puts e.message; exit 1; end' "$file" 2>&1
        return $?
    fi
    return 0
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
    config_link_base="$HOME/.espanso_config_link/match/base.yml"

    # Force-hydrate the config before trusting the readiness check: a dataless
    # Proton placeholder reads as empty and would otherwise block startup forever.
    if ! read_hydrated "$config_link_base" >/dev/null; then
        log "Config link base.yml not ready yet (empty or dataless placeholder)"
        exit 0
    fi

    # Catch a bad edit early: a YAML error makes espanso silently skip the whole
    # match group (0 matches). Warn loudly but still launch so any other valid
    # configs continue to load.
    if ! yaml_error="$(validate_yaml "$config_link_base")"; then
        log "WARNING: base.yml has invalid YAML; espanso will skip it (0 matches from it):"
        log "  ${yaml_error}"
    fi

    log "Launching Espanso"
    open -a "$ESPANSO_APP"
else
    log "Espanso already running"
fi
