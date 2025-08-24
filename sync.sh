#!/bin/bash

# Change to script's directory to ensure we find config and hooks
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

# Read verbose option (default to false)
VERBOSE=$(parse_config options verbose)
VERBOSE=${VERBOSE:-false}

# Read progress and stats options (default to true)
PROGRESS=$(parse_config options progress)
PROGRESS=${PROGRESS:-true}
SHOW_STATS=$(parse_config options show_stats)
SHOW_STATS=${SHOW_STATS:-true}

# Convert comma-separated strings to arrays
IFS=',' read -ra SOURCE_ARRAY <<<"$SOURCE_DIRS"
IFS=',' read -ra EXCLUDE_ARRAY <<<"$EXCLUDE_PATTERNS"

# === Display Backup Summary ===
BACKUP_START_TIME=$(date +%s)
BACKUP_START_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')

echo "============================================"
echo "          RSYNC BACKUP SUMMARY"
echo "============================================"
echo "🕐 Start Time: $BACKUP_START_DISPLAY"
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
echo "🔍 Verbose Mode: $(if [[ "$VERBOSE" == "true" ]]; then echo "ENABLED 📊"; else echo "DISABLED 🔇"; fi)"
echo "📊 Progress Bars: $(if [[ "$PROGRESS" == "true" ]]; then echo "ENABLED 📈"; else echo "DISABLED 📉"; fi)"
echo "📈 Transfer Stats: $(if [[ "$SHOW_STATS" == "true" ]]; then echo "ENABLED 📊"; else echo "DISABLED 📉"; fi)"
echo
echo "============================================"
echo

# === Execute Pre-Sync Hooks ===
PRE_HOOKS_START_TIME=$(date +%s)
PRE_HOOKS_DURATION=0
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
PRE_HOOKS_END_TIME=$(date +%s)
PRE_HOOKS_DURATION=$((PRE_HOOKS_END_TIME - PRE_HOOKS_START_TIME))

# === Sync Function ===
SYNC_START_TIME=$(date +%s)
for src in "${SOURCE_ARRAY[@]}"; do
    # Trim leading/trailing spaces
    src=$(echo "$src" | sed 's/^[ \t]*//;s/[ \t]*$//')
    [[ -z "$src" ]] && continue

    echo "Syncing: $src"

    # Record start time for this directory
    DIR_START_TIME=$(date +%s)
    DIR_START_DISPLAY=$(date '+%H:%M:%S')
    echo "  🕐 Started at: $DIR_START_DISPLAY"

    # Build rsync exclude args
    RSYNC_EXCLUDES=()
    for pattern in "${EXCLUDE_ARRAY[@]}"; do
        pattern=$(echo "$pattern" | sed 's/^[ \t]*//;s/[ \t]*$//')
        RSYNC_EXCLUDES+=("--exclude=$pattern")
    done

    # Build rsync command with conditional delete options
    RSYNC_CMD=(rsync -av --no-compress --safe-links)
    
    # Add verbose options if enabled
    if [[ "$VERBOSE" == "true" ]]; then
        RSYNC_CMD+=(--verbose --human-readable)
        echo "  → Verbose mode: enabled (detailed file transfer information)"
    else
        echo "  → Verbose mode: disabled (minimal output)"
    fi
    
    # Add progress bar if enabled
    if [[ "$PROGRESS" == "true" ]]; then
        RSYNC_CMD+=(--progress)
        echo "  → Progress bars: enabled (shows transfer progress for each file)"
    else
        echo "  → Progress bars: disabled"
    fi
    
    # Add statistics if enabled
    if [[ "$SHOW_STATS" == "true" ]]; then
        RSYNC_CMD+=(--stats)
        echo "  → Transfer statistics: enabled (shows detailed transfer summary)"
    else
        echo "  → Transfer statistics: disabled"
    fi

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

    # Calculate and display timing for this directory
    DIR_END_TIME=$(date +%s)
    DIR_END_DISPLAY=$(date '+%H:%M:%S')
    DIR_DURATION=$((DIR_END_TIME - DIR_START_TIME))
    DIR_DURATION_FORMATTED=$(printf '%02d:%02d:%02d' $((DIR_DURATION / 3600)) $((DIR_DURATION % 3600 / 60)) $((DIR_DURATION % 60)))

    if [[ $? -eq 0 ]]; then
        echo "  ✅ Sync completed successfully"
    else
        echo "  ❌ Sync failed with exit code $?"
    fi
    echo "  🕐 Finished at: $DIR_END_DISPLAY (Duration: $DIR_DURATION_FORMATTED)"
    echo
done

# Capture sync end time right after sync operations complete
SYNC_END_TIME=$(date +%s)

# === Execute Post-Sync Hooks ===
POST_HOOKS_START_TIME=$(date +%s)
POST_HOOKS_DURATION=0
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
POST_HOOKS_END_TIME=$(date +%s)
POST_HOOKS_DURATION=$((POST_HOOKS_END_TIME - POST_HOOKS_START_TIME))

# Calculate sync-only duration (excluding hooks)
SYNC_DURATION=$((SYNC_END_TIME - SYNC_START_TIME))
SYNC_DURATION_FORMATTED=$(printf '%02d:%02d:%02d' $((SYNC_DURATION / 3600)) $((SYNC_DURATION % 3600 / 60)) $((SYNC_DURATION % 60)))

# Calculate total backup time (including hooks) - AFTER post-sync hooks complete
BACKUP_END_TIME=$(date +%s)
BACKUP_END_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')
TOTAL_DURATION=$((BACKUP_END_TIME - BACKUP_START_TIME))
TOTAL_DURATION_FORMATTED=$(printf '%02d:%02d:%02d' $((TOTAL_DURATION / 3600)) $((TOTAL_DURATION % 3600 / 60)) $((TOTAL_DURATION % 60)))

echo "============================================"
echo "        BACKUP PROCESS COMPLETED"
echo "============================================"
echo "🕐 Start Time:  $BACKUP_START_DISPLAY"
echo "🕐 End Time:    $BACKUP_END_DISPLAY"
echo
echo "📊 Time Breakdown:"
echo "   🔄 Sync Duration: $SYNC_DURATION_FORMATTED"
if [[ $PRE_HOOKS_DURATION -gt 0 ]]; then
    PRE_HOOKS_FORMATTED=$(printf '%02d:%02d:%02d' $((PRE_HOOKS_DURATION / 3600)) $((PRE_HOOKS_DURATION % 3600 / 60)) $((PRE_HOOKS_DURATION % 60)))
    echo "   🔧 Pre-sync hooks: $PRE_HOOKS_FORMATTED"
fi
if [[ $POST_HOOKS_DURATION -gt 0 ]]; then
    POST_HOOKS_FORMATTED=$(printf '%02d:%02d:%02d' $((POST_HOOKS_DURATION / 3600)) $((POST_HOOKS_DURATION % 3600 / 60)) $((POST_HOOKS_DURATION % 60)))
    echo "   🔧 Post-sync hooks: $POST_HOOKS_FORMATTED"
fi
echo "   ⏱️  Total Time: $TOTAL_DURATION_FORMATTED"
echo "============================================"
