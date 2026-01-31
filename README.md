# pet-cli 🐾

Simple Node.js project manager with **sleep support** for Linux VPS.

Deploy hundreds of pet projects that automatically sleep when idle and wake on HTTP requests.

## Features

- **Sleep mode** — projects stop after idle timeout, wake on first request
- **Always-on mode** — for projects that need to run constantly
- **Memory limits** — hard limits via systemd cgroups
- **Auto-restart** — configurable restart policy on crashes
- **nginx integration** — automatic config generation with SSL via certbot
- **Simple CLI** — `pet deploy`, `pet status`, `pet logs`

## Requirements

- Linux with systemd (Ubuntu 20.04+, Debian 11+)
- Node.js 18+ (for your projects)
- nginx (optional, for domains)
- certbot (optional, for SSL)

## Installation

```bash
# Clone the repo
git clone https://github.com/kuzn5298/pet-cli.git ~/.pet-cli

# Install
~/.pet-cli/install.sh

# Verify
pet --version
```

## Quick Start

```bash
# Deploy a Node.js API with sleep mode (default: 15 min)
pet deploy my-api --port 3000 --dir /opt/apps/my-api

# Deploy always-on project (Next.js, etc)
pet deploy my-frontend --port 3001 --dir /opt/apps/frontend --always-on

# Deploy SPA (React, Vue builds) - no Node.js process needed
pet deploy my-spa --spa --dir /opt/apps/my-spa

# Deploy static files (CDN-style)
pet deploy my-cdn --static --dir /mnt/static

# Check status
pet status

# Add domain with SSL
pet nginx my-api --domain api.example.com
```

## Project Types

| Type              | Use Case            | Example                    |
| ----------------- | ------------------- | -------------------------- |
| `proxy` (default) | Node.js apps, APIs  | NestJS, Express, Next.js   |
| `--spa`           | Single Page Apps    | React, Vue, Angular builds |
| `--static`        | Static file hosting | CDN, images, downloads     |

## Commands

### Project Management

```bash
pet deploy <name> --port <N> [options]   # Deploy new project
pet status [name]                         # Show status
pet list                                  # List all projects
pet start <name>                          # Start/wake project
pet stop <name>                           # Stop (socket stays active)
pet restart <name> [--reset]              # Restart project
pet enable <name>                         # Enable disabled project
pet disable <name>                        # Fully disable (including socket)
pet remove <name>                         # Remove from management
```

### Deploy Options

```bash
--port <N>              # Port number (required)
--dir <path>            # Project directory (default: /opt/apps/<name>)
--cmd <command>         # Start command (default: node dist/main.js)
--always-on             # Don't sleep
--sleep <time>          # Sleep timeout (default: 15m)
--memory <limit>        # Memory limit (default: 100M)
--restart-attempts <N>  # Restart attempts (default: 3)
--restart-always        # Infinite restart attempts
```

### Logs & Debugging

```bash
pet logs <name>         # View logs
pet logs <name> -f      # Follow logs (tail -f)
pet logs <name> -n 100  # Last 100 lines
pet crashes [name]      # Show crash history
```

### Configuration

```bash
pet config <name>                  # Show config
pet config <name> --sleep 30m      # Change sleep timeout
pet config <name> --always-on      # Convert to always-on
pet config <name> --memory 200M    # Change memory limit
```

### Nginx & Domains

```bash
pet nginx <name> --domain <domain>  # Add domain + SSL
pet nginx <name> --show             # Show nginx config
pet nginx <name> --enable           # Enable config
pet nginx <name> --disable          # Disable config
pet nginx <name> --remove           # Remove config
pet nginx --list                    # List all configs
pet nginx --renew-ssl               # Renew SSL certificates
```

## Sleep Mode

When a project is deployed with sleep mode:

1. Only a **socket** listens on the port (minimal resources)
2. First HTTP request **wakes** the service (2-5 sec cold start)
3. After idle timeout, service **stops** automatically
4. Socket stays active, ready for next request

Perfect for portfolios with many demo projects.

## File Structure

```
~/.pet-cli/                    # Installation directory
├── pet                        # Main CLI script
├── lib/                       # Module scripts
├── templates/                 # Service & nginx templates
└── install.sh                 # Installer

~/.config/pet/                 # Config directory
└── projects/                  # Project configs
    ├── my-api.conf
    └── my-frontend.conf

~/.config/systemd/user/        # Systemd units
├── pet-my-api.service
├── pet-my-api.socket
├── pet-my-frontend.service
└── ...
```

## Updating

```bash
pet update
# or manually:
cd ~/.pet-cli && git pull && ./install.sh
```

## Uninstalling

```bash
~/.pet-cli/uninstall.sh
```

## Integration with OpenClaw

pet-cli works great with [OpenClaw](https://openclaw.ai) for AI-powered monitoring:

```bash
# OpenClaw can run these commands
pet status              # Check all projects
pet logs my-api -n 20   # View recent logs
pet restart my-api      # Restart crashed project
```

## License

MIT
