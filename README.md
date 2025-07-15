# Rsync Backup

A simple bash script for automated backups using rsync with configurable sources and excludes.

## Features

- 🔄 **Incremental backups** using rsync
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
   ```

4. **Make the script executable and run**

   ```bash
   chmod +x sync.sh
   ./sync.sh
   ```

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
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Feel free to submit issues and pull requests!
