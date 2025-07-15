# Hooks System

The rsync-backup script supports a flexible hooks system that allows you to run custom scripts before and after the sync process.

## Directory Structure

```
hooks/
├── pre-sync/          # Scripts executed BEFORE sync starts
│   ├── 01-cleanup.sh
│   ├── 02-database-backup.sh
│   └── 99-final-prep.sh
└── post-sync/         # Scripts executed AFTER sync completes
    ├── 01-notification.sh
    ├── 02-cleanup-old-backups.sh
    └── 99-final-cleanup.sh
```

## How It Works

1. **Pre-sync hooks** run before any directory synchronization begins
2. **Post-sync hooks** run after all directories have been synchronized
3. Scripts are executed in **alphabetical order** (use numeric prefixes like `01-`, `02-` for control)
4. All scripts must be **executable** (`chmod +x script.sh`)
5. Hook failures **don't stop the backup process** (pre-sync) but are logged

## Creating Hooks

### 1. Create your script

```bash
# Create a new pre-sync hook
nano hooks/pre-sync/03-my-custom-script.sh
```

### 2. Make it executable

```bash
chmod +x hooks/pre-sync/03-my-custom-script.sh
```

### 3. Test your script

```bash
# Test the script independently
./hooks/pre-sync/03-my-custom-script.sh
```

## Hook Script Guidelines

- Start with `#!/bin/bash` shebang
- Use descriptive echo statements for progress
- Handle errors gracefully (`|| true` for non-critical commands)
- Use absolute paths when possible
- Log important actions to syslog or files

## Example Use Cases

### Pre-sync Hooks

- **Database backups** before syncing data directories
- **Clean up temporary files** to reduce sync size
- **Stop services** that might interfere with file consistency
- **Create snapshots** of important data
- **Check disk space** before starting backup

### Post-sync Hooks

- **Send notifications** (email, Slack, etc.)
- **Clean up old backup files** to manage storage
- **Restart services** that were stopped in pre-sync
- **Update monitoring systems** with backup status
- **Generate backup reports**

## Environment Variables

Your hooks have access to these environment variables:

- `$REMOTE_USER` - Remote backup user
- `$REMOTE_HOST` - Remote backup host  
- `$REMOTE_PATH` - Remote backup path
- `$DELETE_REMOTE` - Whether delete mode is enabled

## Error Handling

- **Pre-sync hook failures**: Logged but backup continues
- **Post-sync hook failures**: Logged but don't affect backup success status
- Use `set -e` in your scripts if you want them to exit on first error

## Naming Convention

Use this naming pattern for better organization:

- `01-` to `09-` - System preparation tasks
- `10-` to `19-` - Database/service tasks  
- `20-` to `89-` - Main tasks
- `90-` to `99-` - Cleanup/finalization tasks
