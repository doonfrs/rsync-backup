#!/bin/bash
# Wrapper script for crontab to run sync twice

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# First run: without hooks
./sync.sh --no-hooks >> sync.log 2>&1

# Second run: with hooks
./sync.sh >> sync.log 2>&1