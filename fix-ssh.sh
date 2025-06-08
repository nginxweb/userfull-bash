#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name: fix-ssh-config.sh
# Description: This script searches for all config files under /etc/ssh and 
#              replaces "PasswordAuthentication no" with "yes"
#              and "PermitRootLogin no" with "yes". It also restarts the SSH service.
# Compatibility: Works with CentOS, Ubuntu, Debian, AlmaLinux
# Author: Eisa Mohammadzadeh
# -----------------------------------------------------------------------------

echo "🔍 Starting scan in /etc/ssh for SSH configuration updates..."

# Array to track which files were modified
changed_files=()

# Search and process each config file under /etc/ssh
while IFS= read -r -d '' file; do
    # Check if file contains either directive set to 'no'
    if grep -qE "^\s*(PasswordAuthentication|PermitRootLogin)\s+no" "$file"; then
        cp "$file" "$file.bak"  # Create a backup of the file
        sed -i -E 's/^\s*PasswordAuthentication\s+no/PasswordAuthentication yes/g' "$file"
        sed -i -E 's/^\s*PermitRootLogin\s+no/PermitRootLogin yes/g' "$file"
        
        echo "✅ Updated: $file"
        changed_files+=("$file")
    fi
done < <(find /etc/ssh -type f -print0)

# If no changes were made
if [ ${#changed_files[@]} -eq 0 ]; then
    echo "ℹ️ No matching configurations found to update."
else
    echo -e "\n📁 Modified files:"
    for file in "${changed_files[@]}"; do
        echo "  - $file"
    done
fi

# Restart the SSH service based on the system
echo -e "\n🔁 Restarting SSH service..."

if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files | grep -q sshd.service; then
        systemctl restart sshd && echo "✅ sshd restarted successfully."
    elif systemctl list-unit-files | grep -q ssh.service; then
        systemctl restart ssh && echo "✅ ssh restarted successfully."
    else
        echo "⚠️ SSH service not found in systemd."
    fi
else
    service sshd restart 2>/dev/null || service ssh restart 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ SSH service restarted."
    else
        echo "⚠️ Could not restart SSH service."
    fi
fi
