#!/usr/bin/env bash
# =============================================================================
#  Workshop Dashboard — Full Installation Script
#  Run as root on Ubuntu 24.04 (DigitalOcean droplet)
#  Usage: sudo bash install.sh
# =============================================================================
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash install.sh"

# ── Config (edit these if needed) ────────────────────────────────────────────
TEAMS_COUNT=25
WEB_ROOT="/var/www/workshop"
SHARED_DIR="/var/workshop/submissions"   # flat mirror of team submission dirs
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Update system ──────────────────────────────────────────────────────────
info "Updating package lists…"
apt-get update -qq

# ── 2. Install Nginx + PHP ────────────────────────────────────────────────────
info "Installing Nginx and PHP-FPM…"
apt-get install -y -qq nginx php8.3-fpm php8.3-cli

# ── 3. Create shared submissions mirror directory ─────────────────────────────
# The web server (www-data) cannot read /home/teamXX — we use a dedicated
# world-accessible mirror directory owned by a workshop group.
info "Creating submission mirror directory at ${SHARED_DIR}…"

groupadd -f workshop
mkdir -p "${SHARED_DIR}"
chown root:workshop "${SHARED_DIR}"
chmod 2750 "${SHARED_DIR}"          # setgid: new dirs inherit group

# Add www-data to workshop group
usermod -aG workshop www-data

# ── 4. Create per-team submission mirrors ─────────────────────────────────────
info "Setting up per-team folders…"

for i in $(seq -w 1 ${TEAMS_COUNT}); do
    TEAM="team${i}"

    # Create team account if it doesn't exist
    if ! id "${TEAM}" &>/dev/null; then
        useradd -m -s /bin/bash "${TEAM}"
        echo "${TEAM}:ChangeMeASAP123!" | chpasswd
        info "  Created user ${TEAM}"
    fi

    # Real submission folder under /home
    REAL_SUB="/home/${TEAM}/submissions"
    mkdir -p "${REAL_SUB}"
    chown "${TEAM}:workshop" "${REAL_SUB}"
    chmod 2770 "${REAL_SUB}"        # team + workshop group can write

    # Mirror directory in shared area (www-data reads here)
    MIRROR="${SHARED_DIR}/${TEAM}"
    mkdir -p "${MIRROR}"
    chown "${TEAM}:workshop" "${MIRROR}"
    chmod 2770 "${MIRROR}"

    # Bind-mount the real dir onto the mirror so www-data can read it
    # (alternative: inotify sync — bind mount is simpler)
    if ! mountpoint -q "${MIRROR}"; then
        mount --bind "${REAL_SUB}" "${MIRROR}"
    fi
done

# Persist bind mounts across reboots
info "Persisting bind mounts in /etc/fstab…"
for i in $(seq -w 1 ${TEAMS_COUNT}); do
    TEAM="team${i}"
    REAL_SUB="/home/${TEAM}/submissions"
    MIRROR="${SHARED_DIR}/${TEAM}"
    FSTAB_ENTRY="${REAL_SUB} ${MIRROR} none bind 0 0"
    if ! grep -qF "${FSTAB_ENTRY}" /etc/fstab; then
        echo "${FSTAB_ENTRY}" >> /etc/fstab
    fi
done

# ── 5. Deploy web files ───────────────────────────────────────────────────────
info "Deploying web files to ${WEB_ROOT}…"
mkdir -p "${WEB_ROOT}/api"

cp "${SOURCE_DIR}/public/index.html"        "${WEB_ROOT}/index.html"
cp "${SOURCE_DIR}/api/submissions.php"      "${WEB_ROOT}/api/submissions.php"
cp "${SOURCE_DIR}/api/download.php"         "${WEB_ROOT}/api/download.php"

chown -R www-data:www-data "${WEB_ROOT}"
chmod -R 750 "${WEB_ROOT}"
chmod 644 "${WEB_ROOT}/index.html"
chmod 640 "${WEB_ROOT}/api/"*.php

# ── 6. Configure Nginx ────────────────────────────────────────────────────────
info "Configuring Nginx…"
cp "${SOURCE_DIR}/config/nginx-workshop.conf" /etc/nginx/sites-available/workshop

# Remove default site if present
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/workshop /etc/nginx/sites-enabled/workshop

nginx -t || error "Nginx config test failed — check /etc/nginx/sites-available/workshop"

# ── 7. Configure PHP-FPM ──────────────────────────────────────────────────────
info "Tuning PHP-FPM…"
PHP_POOL="/etc/php/8.3/fpm/pool.d/www.conf"

# Run PHP-FPM as www-data (already default, just ensure)
sed -i 's/^user = .*/user = www-data/'   "${PHP_POOL}"
sed -i 's/^group = .*/group = www-data/' "${PHP_POOL}"

# ── 8. Firewall (ufw) ─────────────────────────────────────────────────────────
info "Opening port 80 in ufw (if active)…"
if ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp
    ufw allow 22/tcp   # keep SSH open!
fi

# ── 9. Start / restart services ───────────────────────────────────────────────
info "Starting services…"
systemctl enable php8.3-fpm nginx
systemctl restart php8.3-fpm
systemctl restart nginx

# ── Done ──────────────────────────────────────────────────────────────────────
SERVER_IP=$(curl -s http://checkip.amazonaws.com || echo "<your-server-ip>")

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}✓ Workshop Dashboard installed successfully!${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Dashboard URL:  http://${SERVER_IP}"
echo "  Web root:       ${WEB_ROOT}"
echo "  Submissions:    ${SHARED_DIR}"
echo ""
echo -e "  ${YELLOW}⚠  Change default team passwords immediately:${NC}"
echo "     passwd teamXX"
echo ""
echo "  To check Nginx:  systemctl status nginx"
echo "  To check PHP:    systemctl status php8.3-fpm"
echo "  Access log:      tail -f /var/log/nginx/workshop.access.log"
echo ""
