#!/usr/bin/env bash
# =============================================================================
#  Byte2Cloud — SSH Password Auth Fix
#  Enables password login for workshop team accounts
#  Run as root:  sudo bash fix_ssh.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Must be run as root"

SSHD_CONFIG="/etc/ssh/sshd_config"

# ── Backup original config ────────────────────────────────────────────────────
cp "${SSHD_CONFIG}" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
success "Backed up sshd_config"

# ── Enable password authentication ───────────────────────────────────────────
# Handle both commented and uncommented variants
sed -i \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
    -e 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' \
    "${SSHD_CONFIG}"

# If the line didn't exist at all, append it
grep -q "^PasswordAuthentication" "${SSHD_CONFIG}" \
    || echo "PasswordAuthentication yes" >> "${SSHD_CONFIG}"

# ── Keep root login restricted (only root keeps key-based) ───────────────────
# This scopes password auth to team accounts only via a Match block
# Remove any existing Byte2Cloud Match block first to avoid duplicates
sed -i '/# Byte2Cloud workshop block/,/# end Byte2Cloud/d' "${SSHD_CONFIG}"

cat >> "${SSHD_CONFIG}" << 'EOF'

# Byte2Cloud workshop block — allow team accounts to use passwords
Match User team*
    PasswordAuthentication yes
    PubkeyAuthentication yes
# end Byte2Cloud
EOF

success "SSH config updated"

# ── Validate config before restarting ────────────────────────────────────────
info "Validating sshd config..."
sshd -t && success "Config valid" || die "sshd config has errors — check ${SSHD_CONFIG}"

# ── Restart SSH service ───────────────────────────────────────────────────────
info "Restarting SSH service..."
if systemctl is-active --quiet ssh 2>/dev/null; then
    systemctl restart ssh
elif systemctl is-active --quiet sshd 2>/dev/null; then
    systemctl restart sshd
else
    service ssh restart 2>/dev/null || service sshd restart
fi

success "SSH service restarted"

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
info "Current effective settings:"
sshd -T | grep -E "passwordauthentication|pubkeyauthentication|permitemptypasswords"

echo ""
echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
echo -e "${BOLD}  SSH fix applied — teams can now log in${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
echo ""
echo "  Test with:"
echo "    ssh team01@$(hostname -I | awk '{print $1}')"
echo "    password: Byte2Cloud@2025"
echo ""
echo -e "${YELLOW}  Note: root login still requires a key (unchanged)${NC}"
