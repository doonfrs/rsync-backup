#!/bin/bash

# Change to script's directory to ensure we find config and hooks
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="backup.conf"

# === Parse command line arguments ===
SKIP_HOOKS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-hooks)
            SKIP_HOOKS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --no-hooks    Skip execution of pre-sync and post-sync hooks"
            echo "  -h, --help    Show this help message"
            echo
            echo "Examples:"
            echo "  $0                    # Run backup with hooks (default)"
            echo "  $0 --no-hooks        # Run backup without hooks"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

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

# === Perform Sync Function ===
# Arguments:
#   $1 - Source array name (pass array name, not the array itself)
#   $2 - Destination (local path or remote user@host:path)
#   $3 - Phase description (for display)
function perform_sync() {
    local -n sources=$1
    local destination=$2
    local phase=$3

    echo "============================================"
    echo "  $phase"
    echo "============================================"
    echo

    local phase_start_time=$(date +%s)

    for src in "${sources[@]}"; do
        # Trim leading/trailing spaces
        src=$(echo "$src" | sed 's/^[ \t]*//;s/[ \t]*$//')
        [[ -z "$src" ]] && continue

        echo "Syncing: $src → $destination"

        # Record start time for this directory
        local dir_start_time=$(date +%s)
        local dir_start_display=$(date '+%H:%M:%S')
        echo "  🕐 Started at: $dir_start_display"

        # Build rsync exclude args
        RSYNC_EXCLUDES=()
        for pattern in "${EXCLUDE_ARRAY[@]}"; do
            pattern=$(echo "$pattern" | sed 's/^[ \t]*//;s/[ \t]*$//')
            RSYNC_EXCLUDES+=("--exclude=$pattern")
        done

        # Build rsync command with conditional options
        RSYNC_CMD=(rsync -av --no-compress --safe-links)

        # Add verbose options if enabled
        if [[ "$VERBOSE" == "true" ]]; then
            RSYNC_CMD+=(--verbose --human-readable)
            echo "  → Verbose mode: enabled"
        else
            echo "  → Verbose mode: disabled"
        fi

        # Add progress bar if enabled
        if [[ "$PROGRESS" == "true" ]]; then
            RSYNC_CMD+=(--progress)
            echo "  → Progress bars: enabled"
        else
            echo "  → Progress bars: disabled"
        fi

        # Add statistics if enabled
        if [[ "$SHOW_STATS" == "true" ]]; then
            RSYNC_CMD+=(--stats)
            echo "  → Transfer statistics: enabled"
        else
            echo "  → Transfer statistics: disabled"
        fi

        # Add delete options if enabled
        if [[ "$DELETE_REMOTE" == "true" ]]; then
            RSYNC_CMD+=(--delete --force --delete-excluded)
            echo "  → Delete mode: enabled"
        else
            echo "  → Delete mode: disabled"
        fi

        # Execute rsync (with sudo if enabled)
        if [[ "$USE_SUDO" == "true" ]]; then
            sudo "${RSYNC_CMD[@]}" \
                "${RSYNC_EXCLUDES[@]}" \
                "$src" "$destination"
        else
            "${RSYNC_CMD[@]}" \
                "${RSYNC_EXCLUDES[@]}" \
                "$src" "$destination"
        fi

        local rsync_exit=$?

        # Calculate and display timing for this directory
        local dir_end_time=$(date +%s)
        local dir_end_display=$(date '+%H:%M:%S')
        local dir_duration=$((dir_end_time - dir_start_time))
        local dir_duration_formatted=$(printf '%02d:%02d:%02d' $((dir_duration / 3600)) $((dir_duration % 3600 / 60)) $((dir_duration % 60)))

        if [[ $rsync_exit -eq 0 ]]; then
            echo "  ✅ Sync completed successfully"
        else
            echo "  ❌ Sync failed with exit code $rsync_exit"
        fi
        echo "  🕐 Finished at: $dir_end_display (Duration: $dir_duration_formatted)"
        echo
    done

    local phase_end_time=$(date +%s)
    local phase_duration=$((phase_end_time - phase_start_time))
    local phase_duration_formatted=$(printf '%02d:%02d:%02d' $((phase_duration / 3600)) $((phase_duration % 3600 / 60)) $((phase_duration % 60)))
    echo "✅ $phase completed in $phase_duration_formatted"
    echo

    return 0
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

# Read sudo option (default to false)
USE_SUDO=$(parse_config options use_sudo)
USE_SUDO=${USE_SUDO:-false}

# Read staging options (default to false)
LOCAL_STAGING=$(parse_config staging local_staging)
LOCAL_STAGING=${LOCAL_STAGING:-false}
STAGING_PATH=$(parse_config staging staging_path)
STAGING_PATH=${STAGING_PATH:-}

# Convert comma-separated strings to arrays
IFS=',' read -ra SOURCE_ARRAY <<<"$SOURCE_DIRS"
IFS=',' read -ra EXCLUDE_ARRAY <<<"$EXCLUDE_PATTERNS"

# Build staging sources array for Phase 5 (sync staging to remote)
STAGING_SOURCES=()
if [[ "$LOCAL_STAGING" == "true" ]]; then
    for src in "${SOURCE_ARRAY[@]}"; do
        src=$(echo "$src" | sed 's/^[ \t]*//;s/[ \t]*$//')
        [[ -z "$src" ]] && continue
        # Extract the directory name from the source path
        dir_name=$(basename "$src")
        STAGING_SOURCES+=("$STAGING_PATH/$dir_name")
    done
fi

# Validate staging configuration
if [[ "$LOCAL_STAGING" == "true" ]]; then
    if [[ -z "$STAGING_PATH" ]]; then
        echo "❌ Error: local_staging is enabled but staging_path is not set in config"
        exit 1
    fi
    # Create staging directory if it doesn't exist
    if [[ ! -d "$STAGING_PATH" ]]; then
        echo "📁 Creating staging directory: $STAGING_PATH"
        mkdir -p "$STAGING_PATH" || {
            echo "❌ Error: Failed to create staging directory: $STAGING_PATH"
            exit 1
        }
    fi
fi

# === Display Backup Summary ===
BACKUP_START_TIME=$(date +%s)
BACKUP_START_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')

echo "============================================"
echo "          RSYNC BACKUP SUMMARY"
echo "============================================"
echo "🕐 Start Time: $BACKUP_START_DISPLAY"
echo
if [[ "$LOCAL_STAGING" == "true" ]]; then
    echo "🚀 Mode: SMART BACKUP (Local Staging)"
    echo "   Staging Path: $STAGING_PATH"
    echo "   Phase 1: sources → staging (no hooks)"
    echo "   Phase 2: pre-hooks + sources → staging"
    echo "   Phase 3: post-hooks"
    echo "   Phase 4: staging → remote (async)"
    echo
fi
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
echo "🔐 Sudo Mode: $(if [[ "$USE_SUDO" == "true" ]]; then echo "ENABLED 🔑"; else echo "DISABLED"; fi)"
echo "🔧 Hooks: $(if [[ "$SKIP_HOOKS" == "true" ]]; then echo "DISABLED ⏭️"; else echo "ENABLED 🔧"; fi)"
echo
echo "============================================"
echo

# === Helper function to execute hooks ===
function execute_hooks() {
    local hook_type=$1  # "pre-sync" or "post-sync"
    local hook_dir="hooks/$hook_type"

    if [[ -d "$hook_dir" ]]; then
        local hooks=("$hook_dir"/*)
        if [[ -e "${hooks[0]}" ]]; then
            echo "🔧 Executing $hook_type hooks..."
            for hook in "${hooks[@]}"; do
                if [[ -f "$hook" && -x "$hook" ]]; then
                    echo "   → Running: $(basename "$hook")"
                    if "$hook"; then
                        echo "   ✅ Hook completed: $(basename "$hook")"
                    else
                        local exit_code=$?
                        echo "   ❌ Hook failed: $(basename "$hook") (exit code: $exit_code)"
                        if [[ "$hook_type" == "pre-sync" ]]; then
                            echo "   ⚠️  Continuing with backup despite hook failure..."
                        fi
                    fi
                fi
            done
            echo
        fi
    fi
}

# === Main Backup Logic ===
SYNC_START_TIME=$(date +%s)
PRE_HOOKS_DURATION=0
POST_HOOKS_DURATION=0
PHASE1_DURATION=0
PHASE2_DURATION=0
REMOTE_SYNC_DURATION=0

if [[ "$LOCAL_STAGING" == "true" ]]; then
    # === SMART MODE: Multi-phase backup with local staging ===

    echo "🚀 SMART MODE ENABLED - Using local staging for minimal downtime"
    echo

    # Phase 1: Initial sync to staging (no hooks, services stay up)
    PHASE1_START=$(date +%s)
    perform_sync SOURCE_ARRAY "$STAGING_PATH" "PHASE 1: Initial sync to local staging (no hooks)"
    PHASE1_END=$(date +%s)
    PHASE1_DURATION=$((PHASE1_END - PHASE1_START))

    # Pre-hooks (stop services)
    if [[ "$SKIP_HOOKS" == "true" ]]; then
        echo "⏭️  Skipping pre-sync hooks (--no-hooks flag specified)"
        echo
    else
        echo "============================================"
        echo "  PHASE 2: Pre-Sync Hooks (Stopping Services)"
        echo "============================================"
        echo
        PRE_HOOKS_START_TIME=$(date +%s)
        execute_hooks "pre-sync"
        PRE_HOOKS_END_TIME=$(date +%s)
        PRE_HOOKS_DURATION=$((PRE_HOOKS_END_TIME - PRE_HOOKS_START_TIME))
    fi

    # Phase 2: Final sync to staging (services down, capture committed data)
    PHASE2_START=$(date +%s)
    perform_sync SOURCE_ARRAY "$STAGING_PATH" "PHASE 3: Final sync to staging (services down)"
    PHASE2_END=$(date +%s)
    PHASE2_DURATION=$((PHASE2_END - PHASE2_START))

    # Post-hooks (start services)
    if [[ "$SKIP_HOOKS" == "true" ]]; then
        echo "⏭️  Skipping post-sync hooks (--no-hooks flag specified)"
        echo
    else
        echo "============================================"
        echo "  PHASE 4: Post-Sync Hooks (Starting Services)"
        echo "============================================"
        echo
        POST_HOOKS_START_TIME=$(date +%s)
        execute_hooks "post-sync"
        POST_HOOKS_END_TIME=$(date +%s)
        POST_HOOKS_DURATION=$((POST_HOOKS_END_TIME - POST_HOOKS_START_TIME))
    fi

    echo "✅ Services are back up! Remote sync will now proceed independently."
    echo

    # Phase 3: Sync staging to remote (services already up)
    REMOTE_START=$(date +%s)
    perform_sync STAGING_SOURCES "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}" "PHASE 5: Sync staging to remote"
    REMOTE_END=$(date +%s)
    REMOTE_SYNC_DURATION=$((REMOTE_END - REMOTE_START))

else
    # === NORMAL MODE: Traditional backup ===

    # Pre-hooks
    PRE_HOOKS_START_TIME=$(date +%s)
    if [[ "$SKIP_HOOKS" == "true" ]]; then
        echo "⏭️  Skipping pre-sync hooks (--no-hooks flag specified)"
        echo
    else
        execute_hooks "pre-sync"
    fi
    PRE_HOOKS_END_TIME=$(date +%s)
    PRE_HOOKS_DURATION=$((PRE_HOOKS_END_TIME - PRE_HOOKS_START_TIME))

    # Sync to remote
    perform_sync SOURCE_ARRAY "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}" "SYNC: Backing up to remote"

    # Post-hooks
    POST_HOOKS_START_TIME=$(date +%s)
    if [[ "$SKIP_HOOKS" == "true" ]]; then
        echo "⏭️  Skipping post-sync hooks (--no-hooks flag specified)"
        echo
    else
        execute_hooks "post-sync"
    fi
    POST_HOOKS_END_TIME=$(date +%s)
    POST_HOOKS_DURATION=$((POST_HOOKS_END_TIME - POST_HOOKS_START_TIME))
fi

SYNC_END_TIME=$(date +%s)

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

if [[ "$LOCAL_STAGING" == "true" ]]; then
    # Smart mode breakdown
    echo "📊 Smart Mode Time Breakdown:"

    # Calculate staging time (Phases 1-4: all local operations)
    STAGING_TIME=$((PHASE1_DURATION + PRE_HOOKS_DURATION + PHASE2_DURATION + POST_HOOKS_DURATION))
    STAGING_TIME_FORMATTED=$(printf '%02d:%02d:%02d' $((STAGING_TIME / 3600)) $((STAGING_TIME % 3600 / 60)) $((STAGING_TIME % 60)))
    echo "   📦 Local Staging Time: $STAGING_TIME_FORMATTED"

    if [[ $PHASE1_DURATION -gt 0 ]]; then
        PHASE1_FORMATTED=$(printf '%02d:%02d:%02d' $((PHASE1_DURATION / 3600)) $((PHASE1_DURATION % 3600 / 60)) $((PHASE1_DURATION % 60)))
        echo "      ├─ Phase 1 (Initial sync): $PHASE1_FORMATTED"
    fi
    if [[ $PRE_HOOKS_DURATION -gt 0 ]]; then
        PRE_HOOKS_FORMATTED=$(printf '%02d:%02d:%02d' $((PRE_HOOKS_DURATION / 3600)) $((PRE_HOOKS_DURATION % 3600 / 60)) $((PRE_HOOKS_DURATION % 60)))
        echo "      ├─ Phase 2 (Pre-hooks): $PRE_HOOKS_FORMATTED"
    fi
    if [[ $PHASE2_DURATION -gt 0 ]]; then
        PHASE2_FORMATTED=$(printf '%02d:%02d:%02d' $((PHASE2_DURATION / 3600)) $((PHASE2_DURATION % 3600 / 60)) $((PHASE2_DURATION % 60)))
        echo "      ├─ Phase 3 (Final sync): $PHASE2_FORMATTED"
    fi
    if [[ $POST_HOOKS_DURATION -gt 0 ]]; then
        POST_HOOKS_FORMATTED=$(printf '%02d:%02d:%02d' $((POST_HOOKS_DURATION / 3600)) $((POST_HOOKS_DURATION % 3600 / 60)) $((POST_HOOKS_DURATION % 60)))
        echo "      └─ Phase 4 (Post-hooks): $POST_HOOKS_FORMATTED"
    fi

    if [[ $REMOTE_SYNC_DURATION -gt 0 ]]; then
        REMOTE_FORMATTED=$(printf '%02d:%02d:%02d' $((REMOTE_SYNC_DURATION / 3600)) $((REMOTE_SYNC_DURATION % 3600 / 60)) $((REMOTE_SYNC_DURATION % 60)))
        echo "   🌐 Remote Backup Time: $REMOTE_FORMATTED"
    fi
    echo
    echo "   ⏱️  Total Time: $TOTAL_DURATION_FORMATTED"
else
    # Normal mode breakdown
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
fi
echo "============================================"
