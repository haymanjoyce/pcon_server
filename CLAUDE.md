# CLAUDE.md — logbooklm_server

This file provides persistent context for Claude Code. Read it at the start of every session.

---

## Purpose

This repo documents the configuration and provisioning of the Hetzner VPS that hosts `LogbookLM`. It contains setup scripts and hardening scripts to allow the server to be fully reprovisioned from scratch.

This is **not** an application repo. Do not put application code here.

---

## Server Specs

| Property | Value |
|----------|-------|
| Provider | Hetzner Cloud |
| Hostname | pcon |
| IP | 89.167.98.167 |
| OS | Ubuntu 24.04 LTS |
| CPU | ARM64 (Ampere), 2 vCPU |
| RAM | 4GB |
| Admin user | richard |
| Domain | logbooklm.com |

---

## Directory Layout

```
/home/richard/
  logbooklm_server/             ← this repo
    setup.sh               ← full provisioning script (run on fresh server)
    harden.sh              ← security hardening (run as sudo once)
    nginx_setup.sh         ← Nginx + SSL setup (run as sudo once per app)
    CLAUDE.md              ← this file
    README.md              ← minimal placeholder

/opt/logbooklm/
  app/                     ← LogbookLM source code (git repo → haymanjoyce/logbooklm)

/var/logbooklm/
  projects/
    pcon_doc/              ← user content (docs, evidence, index_store)
      docs/
      evidence/
      index_store/
      members/
  users/
    richard/               ← user profile folder (future auth)
```

---

## Installed Software

| Package | Version |
|---------|---------|
| Ubuntu | 24.04 LTS |
| Python | 3.12.3 |
| Git | 2.43.0 |
| Claude Code | 2.1.66 |

---

## Scripts

### setup.sh
Full provisioning script. Run on a fresh Ubuntu 24.04 server as the target user. Installs Python, Git, Claude Code (native installer — no Node.js required), and Poetry. Downloads installers to a temp file before executing.

```bash
bash /home/richard/logbooklm_server/setup.sh
```

### harden.sh
Security hardening. Run once after provisioning. Requires sudo.

```bash
sudo bash /home/richard/logbooklm_server/harden.sh
```

Applies:
- SSH: disables password auth, disables root login, limits MaxAuthTries to 3
- fail2ban: bans IPs after 5 failed SSH attempts for 1 hour
- unattended-upgrades: auto-applies security patches, auto-reboots at 03:00 UTC

### nginx_setup.sh
Nginx + SSL setup. Run once per application deployment. Requires sudo.

```bash
sudo bash /home/richard/logbooklm_server/nginx_setup.sh
```

---

## Security Status

| Control | Setting | Status |
|---------|---------|--------|
| SSH password auth | PasswordAuthentication no | ✅ |
| SSH root login | PermitRootLogin no | ✅ |
| SSH max auth tries | MaxAuthTries 3 | ✅ |
| fail2ban sshd jail | Bans after 5 failures for 1h | ✅ |
| unattended-upgrades | Security patches auto-applied | ✅ |
| Auto-reboot after patches | 03:00 UTC | ✅ |
| .env permissions | 600 richard:richard | ✅ |

---

## tmux

Persistent named session `main` configured. Every SSH login auto-attaches to it.

```bash
Ctrl-B c    # new window
Ctrl-B 1    # switch to window 1
Ctrl-B 2    # switch to window 2
Ctrl-B d    # detach (session keeps running)
```

---

## Firewall (ufw)

```
22/tcp    ← SSH
80/tcp    ← HTTP (redirects to HTTPS)
443/tcp   ← HTTPS
```

Check status:
```bash
sudo ufw status
```

---

## Nginx

Config: `/etc/nginx/sites-available/logbooklm.com`

- `/` — serves `/opt/logbooklm/app/frontend/dist/` (React static build)
- `/api/` — proxied to `http://127.0.0.1:8000/api/`
- `/api/chat/ws` — WebSocket proxied to FastAPI
- SSL via Let's Encrypt (auto-renews via certbot timer)
- HTTP Basic Auth via `/etc/nginx/.htpasswd`

```bash
sudo nginx -t                  # test config
sudo systemctl reload nginx    # apply changes
sudo certbot renew --dry-run   # test cert renewal
```

---

## MCP Observer Server

Read-only observer MCP server allowing claude.ai to monitor Claude Code sessions in real time.

| Property | Value |
|----------|-------|
| Code | `/opt/logbooklm/mcp/server.py` (FastMCP) |
| Port | 8765 (127.0.0.1 only) |
| Public URL | `https://mcp.logbooklm.com/mcp` |
| Tunnel | Cloudflare Tunnel `mcp-server` (ID: `f2f73de9-fcca-40ec-95ce-eee3c9d6d82e`) |
| Auth | Bearer token — `MCP_API_KEY` in `/opt/logbooklm/mcp/.env` |
| Session log | `/opt/logbooklm/mcp/.session_log.md` |

### Services

```bash
systemctl --user status logbooklm-mcp      # FastMCP / uvicorn
systemctl --user status cloudflared-mcp    # Cloudflare Tunnel
journalctl --user -u logbooklm-mcp -f
journalctl --user -u cloudflared-mcp -f
```

### Tools exposed

| Tool | Description |
|------|-------------|
| `get_recent_commits(n)` | Last n git commits from `/opt/logbooklm/app` |
| `get_current_diff()` | Current git diff in `/opt/logbooklm/app` |
| `read_session_log()` | Reads `/opt/logbooklm/mcp/.session_log.md` |
| `read_file(path)` | Reads any file under `/opt/logbooklm/` |
| `list_files(directory)` | Lists files in a directory under `/opt/logbooklm/` |

### Configuring claude.ai

In claude.ai MCP settings add:
- URL: `https://mcp.logbooklm.com/mcp`
- Header: `Authorization: Bearer <MCP_API_KEY>`

---

## LogbookLM Service

Managed by systemd user service.

```bash
systemctl --user status logbooklm
systemctl --user restart logbooklm
systemctl --user stop logbooklm
journalctl --user -u logbooklm -f
```

---

## Hetzner Snapshots

Must be created manually from the Hetzner Cloud Console — cannot be triggered from within the server.

1. Go to console.hetzner.cloud
2. Select server → Snapshots tab
3. Create Snapshot — label with date and context (e.g. `pre-update-2026-03-01`)

Recommended: snapshot before any major change.

### Snapshot History

| Date | Label |
|------|-------|
| 2026-02-25 | Post doc_app deployment — full stack live |
| 2026-02-25 | Post README refactor |
| 2026-03-01 | Post repo rename (doc_app → pcon_app) and /var/pcon_app data migration |
| 2026-03-01 | Post GitHub integration removal and CLAUDE.md cleanup |
| 2026-03-04 | Post app rename (pcon_app → doc_app) |
| 2026-03-04 | Post data directory rename (/var/pcon_app → /var/pcon) |
| 2026-03-04 | Post brand rename to LogbookLM (doc_app → logbooklm, /opt/doc_app → /opt/logbooklm, /var/pcon → /var/logbooklm, domain: logbooklm.com) |

---

## Reprovisioning from Scratch

On a fresh Ubuntu 24.04 server:

```bash
# 1. From your local machine — copy SSH key
ssh-copy-id richard@<new-server-ip>

# 2. SSH in and clone logbooklm_server repo
ssh richard@<new-server-ip>
git clone git@github.com:haymanjoyce/logbooklm_server.git /home/richard/logbooklm_server

# 3. Run provisioning script
bash /home/richard/logbooklm_server/setup.sh

# 4. Run security hardening
sudo bash /home/richard/logbooklm_server/harden.sh

# 5. Deploy LogbookLM — see /opt/logbooklm/app/CLAUDE.md
```

---

## Dependency Management

### System packages (automatic)
- unattended-upgrades handles Ubuntu security patches automatically
- Auto-reboot at 03:00 UTC if required

### Manual updates (run periodically)
- Claude Code: auto-updates in the background; or run `curl -fsSL https://claude.ai/install.sh | bash` to force update
- Python: Ubuntu-managed, handled by unattended-upgrades
- Git: Ubuntu-managed, handled by unattended-upgrades

### Before updating anything
- Take a Hetzner snapshot first
- Test the app is healthy after each update

---

## What Claude Code Should Never Do

- Modify application code in `/opt/logbooklm/app/` — that belongs to the logbooklm repo
- Touch user data in `/var/logbooklm/` — that belongs to the application
- Delete or modify SSH keys in `/home/richard/.ssh/`
- Disable or weaken any security hardening (fail2ban, SSH config, ufw)
- Commit `.env` files or any secrets
- Modify CLAUDE.md without being explicitly asked

---

## Current Status

- [x] Server provisioned on Hetzner
- [x] Security hardening applied
- [x] tmux configured
- [x] Claude Code installed
- [x] Nginx configured with SSL
- [x] LogbookLM deployed and running
- [x] setup.sh complete and tested
- [x] harden.sh complete and tested
- [x] nginx_setup.sh complete and tested
- [x] logbooklm_server repo on GitHub (haymanjoyce/logbooklm_server)
- [x] MCP observer server deployed (FastMCP, Cloudflare Tunnel, mcp.logbooklm.com)
