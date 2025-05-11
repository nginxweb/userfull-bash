#!/bin/bash

set -e

echo "➤ Mounting tmpfs on /tmp..."
mount -t tmpfs -o size=2G,nr_inodes=2M tmpfs /tmp

FSTAB_LINE="tmpfs /tmp tmpfs defaults,size=2G,nr_inodes=2M 0 0"

echo "➤ Backing up current /etc/fstab..."
cp /etc/fstab /etc/fstab.bak.$(date +%s)

echo "➤ Removing all lines related to /tmp from fstab (even bind mounts)..."
# Delete any line that references /tmp in any of the first two columns
awk '($1 != "/tmp" && $2 != "/tmp") { print }' /etc/fstab > /etc/fstab.clean
mv /etc/fstab.clean /etc/fstab

echo "➤ Adding tmpfs entry for /tmp..."
echo "$FSTAB_LINE" >> /etc/fstab

echo "➤ Restarting lsws and lscpd services if available..."

if systemctl list-units --type=service | grep -q "lsws.service"; then
    systemctl restart lsws
    echo "✅ lsws restarted"
else
    echo "⚠️ lsws service not found"
fi

if systemctl list-units --type=service | grep -q "lscpd.service"; then
    systemctl restart lscpd
    echo "✅ lscpd restarted"
else
    echo "⚠️ lscpd service not found"
fi

echo "➤ Showing df -ih for /tmp:"
df -ih | grep "/tmp"
