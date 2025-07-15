#!/bin/bash

CONFIG_FILE="backup.conf"

# === Parse INI-like config ===
function parse_config() {
    local section=$1
    local key=$2
    awk -F'=' -v section="[$section]" -v key="$key" '
    $0 == section { found=1; next }
    /^\[.*\]/ { found=0 }
    found && $1 ~ key {
        gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2
        exit
    }' "$CONFIG_FILE"
}

REMOTE_USER=$(parse_config remote user)
REMOTE_HOST=$(parse_config remote host)
REMOTE_PATH=$(parse_config remote path)

# Read comma-separated source dirs and excludes
SOURCE_DIRS=$(parse_config sources dirs)
EXCLUDE_PATTERNS=$(parse_config excludes patterns)

# Read delete option (default to false for safety)
DELETE_REMOTE=$(parse_config options delete_remote)
DELETE_REMOTE=${DELETE_REMOTE:-false}

# Convert comma-separated strings to arrays
IFS=',' read -ra SOURCE_ARRAY <<<"$SOURCE_DIRS"
IFS=',' read -ra EXCLUDE_ARRAY <<<"$EXCLUDE_PATTERNS"

# === Sync Function ===
for src in "${SOURCE_ARRAY[@]}"; do
    # Trim leading/trailing spaces
    src=$(echo "$src" | sed 's/^[ \t]*//;s/[ \t]*$//')
    [[ -z "$src" ]] && continue

    echo "Syncing: $src"

    # Build rsync exclude args
    RSYNC_EXCLUDES=()
    for pattern in "${EXCLUDE_ARRAY[@]}"; do
        pattern=$(echo "$pattern" | sed 's/^[ \t]*//;s/[ \t]*$//')
        RSYNC_EXCLUDES+=("--exclude=$pattern")
    done

    # Build rsync command with conditional delete options
    RSYNC_CMD=(rsync -av --no-compress --safe-links)

    # Add delete options if enabled
    if [[ "$DELETE_REMOTE" == "true" ]]; then
        RSYNC_CMD+=(--delete --force --delete-excluded)
        echo "  → Delete mode: enabled (remote files will be deleted if removed from source)"
    else
        echo "  → Delete mode: disabled (remote files will be preserved even if removed from source)"
    fi

    # Execute rsync
    "${RSYNC_CMD[@]}" \
        "${RSYNC_EXCLUDES[@]}" \
        "$src" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
done
