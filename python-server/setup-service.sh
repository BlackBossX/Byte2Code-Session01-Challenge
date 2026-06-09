#!/usr/bin/env bash
# =============================================================================
#  Workshop Dashboard Service Installer
#  Creates a systemd service to run server.py automatically on boot.
#  Usage: sudo bash setup-service.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Run: sudo bash setup-service.sh"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_SCRIPT="${SCRIPT_DIR}/server.py"
SERVICE_NAME="workshop-dashboard"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if [[ ! -f "${SERVER_SCRIPT}" ]]; then
    error "Could not find server.py at ${SERVER_SCRIPT}"
fi

# Ensure server.py is executable
chmod +x "${SERVER_SCRIPT}"

info "Creating systemd service file at ${SERVICE_FILE}..."

cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=Workshop Submission Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${SCRIPT_DIR}
ExecStart=/usr/bin/python3 "${SERVER_SCRIPT}"
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

info "Reloading systemd daemon..."
systemctl daemon-reload

info "Enabling ${SERVICE_NAME} service on boot..."
systemctl enable "${SERVICE_NAME}"

info "Starting ${SERVICE_NAME} service..."
systemctl restart "${SERVICE_NAME}"

# Try to get the local IP address
LOCAL_IP=$(hostname -I | awk '{print $1}' || echo "<your-server-ip>")
PORT=8080

# Check service status
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    info "Service status: Active and Running!"
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo -e "  ${GREEN}✓ Dashboard service installed & started successfully!${NC}"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "  The server is running in the background and will start"
    echo "  automatically if the computer restarts."
    echo ""
    echo "  Access URL:  http://${LOCAL_IP}:${PORT}"
    echo ""
    echo "  Useful Commands:"
    echo "    To check status:   sudo systemctl status ${SERVICE_NAME}"
    echo "    To view logs:     sudo journalctl -u ${SERVICE_NAME} -f"
    echo "    To stop service:   sudo systemctl stop ${SERVICE_NAME}"
    echo "    To restart:        sudo systemctl restart ${SERVICE_NAME}"
    echo ""
else
    error "Service was installed but failed to start. Run 'journalctl -u ${SERVICE_NAME}' for logs."
fi
