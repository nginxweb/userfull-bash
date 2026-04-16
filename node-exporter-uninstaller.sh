#!/bin/bash

# Complete Node Exporter Removal Script
# Run as root

set -e  # Exit immediately if a command exits with a non-zero status

echo "========================================="
echo "Starting Node Exporter removal process..."
echo "========================================="

# 1. Stop and disable the service
echo "[1/7] Stopping and disabling node_exporter service..."
systemctl stop node_exporter.service 2>/dev/null || echo "  - Service already stopped"
systemctl disable node_exporter.service 2>/dev/null || echo "  - Service already disabled"

# 2. Remove the service file and reload systemd
echo "[2/7] Removing systemd service file..."
rm -f /etc/systemd/system/node_exporter.service
systemctl daemon-reload
echo "  - Service file removed and systemd reloaded"

# 3. Remove dedicated user and group
echo "[3/7] Removing node_exporter user and group..."
userdel -r node_exporter 2>/dev/null && echo "  - User 'node_exporter' removed" || echo "  - User 'node_exporter' not found"
groupdel node_exporter 2>/dev/null && echo "  - Group 'node_exporter' removed" || echo "  - Group 'node_exporter' not found"

# 4. Remove the main binary executable
echo "[4/7] Removing binary executable..."
if [ -f /usr/local/bin/node_exporter ]; then
    rm -f /usr/local/bin/node_exporter
    echo "  - Binary removed from /usr/local/bin/"
else
    echo "  - Binary not found at /usr/local/bin/"
fi

# 5. Remove configuration and data directories
echo "[5/7] Removing configuration directory..."
if [ -d /etc/node_exporter ]; then
    rm -rf /etc/node_exporter
    echo "  - Config directory /etc/node_exporter removed"
else
    echo "  - Config directory /etc/node_exporter not found"
fi

echo "[6/7] Removing data directory..."
if [ -d /var/lib/node_exporter ]; then
    rm -rf /var/lib/node_exporter
    echo "  - Data directory /var/lib/node_exporter removed"
else
    echo "  - Data directory /var/lib/node_exporter not found"
fi

# 6. Kill any zombie process
echo "[7/7] Killing any remaining processes..."
pkill -9 node_exporter 2>/dev/null && echo "  - Remaining processes killed" || echo "  - No running processes found"

echo ""
echo "========================================="
echo "Final Verification"
echo "========================================="

# Check service status
echo -n "Service status: "
systemctl status node_exporter.service 2>&1 | head -n 1 || echo "✓ Service not found (OK)"

# Check binary
echo -n "Binary file: "
which node_exporter 2>/dev/null && echo "✗ Binary still exists!" || echo "✓ Binary removed (OK)"

# Check running process
echo -n "Running process: "
ps aux | grep -q "[n]ode_exporter" && echo "✗ Process still running!" || echo "✓ No process running (OK)"

# Check config directory
echo -n "Config directory: "
ls -ld /etc/node_exporter 2>/dev/null && echo "✗ Config directory still exists!" || echo "✓ Config directory removed (OK)"

# Check data directory
echo -n "Data directory: "
ls -ld /var/lib/node_exporter 2>/dev/null && echo "✗ Data directory still exists!" || echo "✓ Data directory removed (OK)"

echo ""
echo "========================================="
echo "Node Exporter removal completed!"
echo "========================================="
