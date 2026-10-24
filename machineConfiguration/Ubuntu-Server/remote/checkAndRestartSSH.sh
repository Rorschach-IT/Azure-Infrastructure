#!/usr/bin/env bash
# ============================================
# Check whether SSH is active and restart it if not
# Usage: sudo ./checkAndRestartSsh.sh [ssh|sshd]
# ============================================

SERVICE="${1:-ssh}"

if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl is not available on this system."
    exit 1
fi

echo "Checking the current state of the $SERVICE service..."

if systemctl is-active --quiet "$SERVICE"; then
    echo "The $SERVICE service is running."
    exit 0
fi

echo "The $SERVICE service is not running. Restarting it..."

systemctl restart "$SERVICE"

if systemctl is-active --quiet "$SERVICE"; then
    echo "The $SERVICE service was restarted successfully."
    exit 0
fi

echo "Failed to restart the $SERVICE service."
exit 1