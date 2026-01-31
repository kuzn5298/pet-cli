# pet-cli 🐾

Simple Node.js project manager for Linux VPS.

## Features

- **Simple deployment** — one command to set up everything
- **Memory limits** — hard limits via systemd cgroups
- **Auto-restart** — configurable restart policy on crashes
- **nginx integration** — automatic config generation with SSL
- **PostgreSQL setup** — creates database and user automatically

## Installation

```bash
git clone https://github.com/kuzn5298/pet-cli.git ~/.pet-cli
~/.pet-cli/install.sh
```

## Quick Start

```bash
# Full setup: directory + database + nginx + SSL
pet setup my-api \
  --port 3000 \
  --domain api.example.com \
  --db myuser:mypassword \
  --memory 200M

# Check status
pet status

# View logs
pet logs my-api -f

# Restart
pet restart my-api
```

## Commands

```bash
pet setup <n>    # Full setup (dir + db + nginx + ssl)
pet deploy <n>      # Deploy without nginx/db
pet status [name]   # Show status
pet start <n>    # Start project
pet stop <n>     # Stop project
pet restart <n>  # Restart project
pet logs <n>     # View logs
pet config <n>   # Show/edit config
pet nginx <n>    # Manage nginx
pet remove <n>   # Remove project
```

## Setup Options

```bash
--port <N>            # Port number (required)
--domain <domain>     # Domain for nginx + SSL
--db <user:pass>      # Create PostgreSQL database
--dir <path>          # Project directory
--cmd <command>       # Start command (default: node dist/main.js)
--memory <limit>      # Memory limit (default: 100M)
--spa                 # SPA type (static + routing)
--static              # Static file type
```

## License

MIT
