# Rsync Backup

A simple bash script for automated backups using rsync with configurable sources and excludes.

## 🌟 Please Star the Repo!

If you find this plugin helpful, please consider starring the repository ⭐! Your support helps others discover this tool and motivates further improvements.

## Features

- 🔄 **Incremental backups** using rsync
- 🚀 **Smart Mode** - Local staging for minimal service downtime
- 📁 **Multiple source directories** support
- 🚫 **Flexible exclude patterns** (file types, directories, etc.)
- ⚙️ **INI-style configuration** file
- 🗑️ **Automatic cleanup** of deleted files on remote
- 🔗 **Safe symbolic link handling**
- 🔧 **Pre/Post-sync hooks** for custom scripts and automation

## Quick Start

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd rsync-backup
   ```

2. **Set up configuration**

   ```bash
   cp backup.conf.example backup.conf
   nano backup.conf
   ```

3. **Configure your backup settings**

   ```ini
   [remote]
   user = your_username
   host = your_server.com
   path = /path/to/backup/destination

   [sources]
   dirs = /home/user/documents, /home/user/pictures, /var/www

   [excludes]
   patterns = *.tmp, *.log, node_modules, .git

   [options]
   delete_remote = false
   verbose = false
   progress = true
   show_stats = true
   ```

4. **Make the script executable and run**

   ```bash
   chmod +x sync.sh
   ./sync.sh                    # Run backup with hooks (default)
   ./sync.sh --no-hooks        # Run backup without hooks
   ```

## Command Line Options

The script supports the following command line options:

- `--no-hooks` - Skip execution of pre-sync and post-sync hooks
- `-h, --help` - Show help message and usage information

## Smart Mode - Minimizing Service Downtime

When your hooks cause service interruptions (e.g., stopping database/email servers), **Smart Mode** provides the optimal solution by using local staging to dramatically reduce service downtime.

### How Smart Mode Works

Smart Mode performs a multi-phase backup process:

1. **Phase 1**: Sync sources → local staging (no hooks, services stay up)
2. **Phase 2**: Run pre-hooks (stop services)
3. **Phase 3**: Sync sources → local staging again (fast, captures final committed data)
4. **Phase 4**: Run post-hooks (start services - **services are back up!**)
5. **Phase 5**: Sync local staging → remote server (happens independently, no service impact)

**Key Benefits:**
- ⚡ **Minimal downtime**: Services are only down during fast local operations (Phases 2-4)
- 🚀 **No network delays**: Local sync is much faster than remote sync
- ✅ **Data consistency**: Final sync captures all committed data after services stop
- 🔄 **Async remote transfer**: Remote backup happens after services are back up

### Enabling Smart Mode

Add these options to your `backup.conf`:

```ini
[staging]
local_staging = true
staging_path = .backup
```

**Note:** The `staging_path` can be:
- Relative path (e.g., `.backup`) - creates folder in the project directory
- Absolute path (e.g., `/home/username/.backup`) - creates folder at specified location

Then run normally:
```bash
./sync.sh
```

The script automatically handles all phases when smart mode is enabled.

## Configuration

The `backup.conf` file uses INI-style sections:

### `[remote]` section

- `user` - Remote server username
- `host` - Remote server hostname or IP
- `path` - Destination path on remote server

### `[sources]` section  

- `dirs` - Comma-separated list of local directories to backup

### `[excludes]` section

- `patterns` - Comma-separated list of patterns to exclude from backup

### `[options]` section

- `delete_remote` - Set to `true` to automatically delete files on remote when they're removed from source (default: `false`)
- `verbose` - Set to `true` to enable detailed output including human-readable file sizes (default: `false`)
- `progress` - Set to `true` to show progress bars for each file during transfer (default: `true`)
- `show_stats` - Set to `true` to display comprehensive transfer statistics (default: `true`)

### `[staging]` section (Smart Mode)

- `local_staging` - Set to `true` to enable Smart Mode with local staging (default: `false`)
- `staging_path` - Path to local staging directory. Can be relative (e.g., `.backup`) or absolute (e.g., `/home/username/.backup`)

## Hooks System

The script supports a flexible hooks system for running custom scripts before and after synchronization:

```
hooks/
├── pre-sync/          # Scripts run BEFORE sync
└── post-sync/         # Scripts run AFTER sync
```

### Quick Hook Setup

1. **Create a hook script:**

   ```bash
   nano hooks/pre-sync/01-database-backup.sh
   ```

2. **Make it executable:**

   ```bash
   chmod +x hooks/pre-sync/01-database-backup.sh
   ```

3. **Scripts run in alphabetical order** - use numeric prefixes for control

### Common Hook Examples

**Pre-sync hooks:**

- Database backups before syncing data directories
- Cleanup temporary files to reduce sync size
- Stop services for consistent file states

**Post-sync hooks:**

- Send notifications (email, Slack, etc.)
- Clean up old backup files
- Update monitoring systems

See [hooks/README.md](hooks/README.md) for detailed documentation and examples.

## Rsync Options Used

The script uses these rsync flags for optimal performance:

- `-a` - Archive mode (preserves permissions, timestamps, etc.)
- `-v` - Verbose output
- `--no-compress` - Skip compression (faster for local networks)
- `--safe-links` - Ignore symlinks that point outside the tree

**When `verbose = true`:**

- `--verbose` - Enhanced verbose output with detailed file transfer information
- `--human-readable` - File sizes displayed in KB, MB, GB format

**When `progress = true`:**

- `--progress` - Progress bars for each file during transfer

**When `show_stats = true`:**

- `--stats` - Comprehensive transfer statistics (file count, bytes transferred, speed, etc.)

**When `delete_remote = true`:**

- `--delete` - Remove files from destination that no longer exist in source
- `--force` - Force deletion of directories even if not empty
- `--delete-excluded` - Delete excluded files from destination

## Prerequisites

- `rsync` installed on both local and remote systems
- SSH access to the remote server
- SSH key-based authentication recommended (to avoid password prompts)

## SSH Key Setup (Recommended)

For automated backups without password prompts:

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
ssh-copy-id user@your_server.com
```

## Automation

Add to crontab for scheduled backups:

```bash
# Run backup every day at 2 AM
0 2 * * * /path/to/rsync-backup/sync.sh

# For production environments with service downtime concerns,
# enable Smart Mode in backup.conf (local_staging = true)
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Feel free to submit issues and pull requests!
