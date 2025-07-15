# Rsync Backup

A simple bash script for automated backups using rsync with configurable sources and excludes.

## Features

- 🔄 **Incremental backups** using rsync
- 📁 **Multiple source directories** support
- 🚫 **Flexible exclude patterns** (file types, directories, etc.)
- ⚙️ **INI-style configuration** file
- 🗑️ **Automatic cleanup** of deleted files on remote
- 🔗 **Safe symbolic link handling**

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

## Rsync Options Used

The script uses these rsync flags for optimal performance:

- `-a` - Archive mode (preserves permissions, timestamps, etc.)
- `-v` - Verbose output
- `--no-compress` - Skip compression (faster for local networks)
- `--delete` - Remove files from destination that no longer exist in source
- `--safe-links` - Ignore symlinks that point outside the tree
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
