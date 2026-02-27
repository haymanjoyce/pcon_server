#!/usr/bin/env bash
# harden.sh — Run once as root to apply system-level hardening
# Usage: sudo bash "$HOME/harden.sh"
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)." >&2
    exit 1
fi

echo "=== Server Hardening Script ==="
echo "Run as: $(whoami)  |  Date: $(date -u)"
echo ""

# ─── 1. SSH: Disable password authentication ─────────────────────────────────
echo "[1/4] Hardening SSH..."
cat > /etc/ssh/sshd_config.d/hardening.conf <<'EOF'
# Disable password-based login — key-based auth only
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

# Limit auth attempts per connection
MaxAuthTries 3

# Disable root login entirely
PermitRootLogin no
EOF
chmod 644 /etc/ssh/sshd_config.d/hardening.conf

# Validate config before restarting
sshd -t && systemctl restart ssh
echo "    SSH hardened and restarted."

# ─── 2. fail2ban: Install and configure ──────────────────────────────────────
echo "[2/4] Installing fail2ban..."
apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
# Ban for 1 hour
bantime  = 3600
# Scan the last 10 minutes
findtime = 600
# 5 failures triggers a ban
maxretry = 5
# Use systemd journal for log backend
backend = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
maxretry = 5
EOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "    fail2ban installed and active."

# ─── 3. unattended-upgrades: Enable auto-remove and auto-reboot ──────────────
echo "[3/4] Enhancing unattended-upgrades..."
# Use a drop-in override file instead of sed-patching the vendor file.
# This is idempotent and survives package upgrades that reset the vendor file.
cat > /etc/apt/apt.conf.d/51local-overrides <<'EOF'
// Local overrides for unattended-upgrades
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF
chmod 644 /etc/apt/apt.conf.d/51local-overrides

systemctl restart unattended-upgrades
echo "    unattended-upgrades enhanced."

# ─── 4. Verify ───────────────────────────────────────────────────────────────
echo "[4/4] Verification..."
echo ""
echo "  SSH:"
sshd -T | grep -E "passwordauthentication|pubkeyauthentication|permitrootlogin|maxauthtries"

echo ""
echo "  fail2ban:"
fail2ban-client status sshd

echo ""
echo "  unattended-upgrades:"
systemctl is-active unattended-upgrades

echo ""
echo "=== Hardening complete ==="
