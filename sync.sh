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

# === Display Backup Summary ===
echo "============================================"
echo "          RSYNC BACKUP SUMMARY"
echo "============================================"
echo
echo "📡 Remote Destination:"
echo "   User: $REMOTE_USER"
echo "   Host: $REMOTE_HOST"
echo "   Path: $REMOTE_PATH"
echo "   Full: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
echo
# Build source directories display with status
SOURCE_DISPLAY=""
MISSING_DIRS=""
for src in "${SOURCE_ARRAY[@]}"; do
    src=$(echo "$src" | sed 's/^[ \t]*//;s/[ \t]*$//')
    [[ -z "$src" ]] && continue
    if [[ -d "$src" ]]; then
        SOURCE_DISPLAY="${SOURCE_DISPLAY}${src}, "
    else
        MISSING_DIRS="${MISSING_DIRS}${src}, "
    fi
done
SOURCE_DISPLAY="${SOURCE_DISPLAY%, }" # Remove trailing comma
MISSING_DIRS="${MISSING_DIRS%, }"     # Remove trailing comma

echo "📁 Source Directories (${#SOURCE_ARRAY[@]}): $SOURCE_DISPLAY"
[[ -n "$MISSING_DIRS" ]] && echo "   ❌ Missing: $MISSING_DIRS"
echo

if [[ ${#EXCLUDE_ARRAY[@]} -gt 0 && -n "${EXCLUDE_ARRAY[0]// /}" ]]; then
    # Build exclude patterns display
    EXCLUDE_DISPLAY=""
    for pattern in "${EXCLUDE_ARRAY[@]}"; do
        pattern=$(echo "$pattern" | sed 's/^[ \t]*//;s/[ \t]*$//')
        [[ -n "$pattern" ]] && EXCLUDE_DISPLAY="${EXCLUDE_DISPLAY}${pattern}, "
    done
    EXCLUDE_DISPLAY="${EXCLUDE_DISPLAY%, }" # Remove trailing comma
    echo "🚫 Exclude Patterns (${#EXCLUDE_ARRAY[@]}): $EXCLUDE_DISPLAY"
    echo
fi
echo "⚙️  Delete Mode: $(if [[ "$DELETE_REMOTE" == "true" ]]; then echo "ENABLED ⚠️"; else echo "DISABLED 🔒"; fi)"
echo
echo "============================================"
echo

# === Execute Pre-Sync Hooks ===
if [[ -d "hooks/pre-sync" ]]; then
    PRE_HOOKS=(hooks/pre-sync/*)
    if [[ -e "${PRE_HOOKS[0]}" ]]; then
        echo "🔧 Executing pre-sync hooks..."
        for hook in "${PRE_HOOKS[@]}"; do
            if [[ -f "$hook" && -x "$hook" ]]; then
                echo "   → Running: $(basename "$hook")"
                if "$hook"; then
                    echo "   ✅ Hook completed: $(basename "$hook")"
                else
                    echo "   ❌ Hook failed: $(basename "$hook") (exit code: $?)"
                    echo "   ⚠️  Continuing with backup despite hook failure..."
                fi
            fi
        done
        echo
    fi
fi

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

    if [[ $? -eq 0 ]]; then
        echo "  ✅ Sync completed successfully"
    else
        echo "  ❌ Sync failed with exit code $?"
    fi
    echo
done

# === Execute Post-Sync Hooks ===
if [[ -d "hooks/post-sync" ]]; then
    POST_HOOKS=(hooks/post-sync/*)
    if [[ -e "${POST_HOOKS[0]}" ]]; then
        echo "🔧 Executing post-sync hooks..."
        for hook in "${POST_HOOKS[@]}"; do
            if [[ -f "$hook" && -x "$hook" ]]; then
                echo "   → Running: $(basename "$hook")"
                if "$hook"; then
                    echo "   ✅ Hook completed: $(basename "$hook")"
                else
                    echo "   ❌ Hook failed: $(basename "$hook") (exit code: $?)"
                fi
            fi
        done
        echo
    fi
fi

echo "============================================"
echo "        BACKUP PROCESS COMPLETED"
echo "============================================"
