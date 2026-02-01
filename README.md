# pet-cli 🐾

Simple Node.js project manager for Linux VPS.

## Features

- **Simple deployment** — one command to set up everything
- **Memory limits** — hard limits via systemd cgroups
- **Auto-restart** — configurable restart policy on crashes
- **nginx integration** — automatic config generation with SSL
- **PostgreSQL setup** — creates database and user automatically
- **Sleep mode** — auto-sleep idle projects to save memory

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
pet setup <n>       # Full setup (dir + db + nginx + ssl)
pet deploy <n>      # Deploy without nginx/db
pet status [name]   # Show status
pet start <n>       # Start project
pet stop <n>        # Stop project
pet restart <n>     # Restart project
pet logs <n>        # View logs
pet config <n>      # Show/edit config
pet nginx <n>       # Manage nginx
pet remove <n>      # Remove project

# Sleep mode
pet sleep <n>       # Put project to sleep
pet wake <n>        # Wake up project
```

## Setup Options

```bash
--port <N>            # Port number (required for proxy type)
--domain <domain>     # Domain for nginx + SSL
--db <user:pass>      # Create PostgreSQL database
--dir <path>          # Project directory
--cmd <command>       # Start command (default: node dist/main.js)
--memory <limit>      # Memory limit (default: 100M)
--spa                 # SPA type (static + routing)
--static              # Static file type
--sleep               # Enable sleep mode
--sleep-timeout <T>   # Sleep timeout (default: 30m)
```

## Sleep Mode

Sleep mode stops idle projects to save memory. When a request comes in, the project wakes up automatically.

```bash
# Enable during setup
pet setup my-api --port 3000 --domain api.example.com --sleep

# Or enable later
pet config my-api --sleep
pet config my-api --sleep-timeout 15m

# Manual control
pet sleep my-api    # Put to sleep
pet wake my-api     # Wake up

# Disable sleep mode
pet config my-api --no-sleep
```

How it works:
- Sleeper timer checks for idle projects every 5 minutes
- Projects without traffic for `--sleep-timeout` duration go to sleep
- Nginx redirects to waker service when project is sleeping
- Waker automatically starts the project on first request

## License

MIT
