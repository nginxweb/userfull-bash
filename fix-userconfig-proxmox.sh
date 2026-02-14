#!/bin/bash

# Proxmox user config .conf fix script
# Input: VMID (prompted if not provided), everything else automated

# Check if VMID was provided as argument
if [ -z "$1" ]; then
    read -p "Enter VMID: " VMID
else
    VMID="$1"
fi

# Validate VMID is numeric
if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
    echo "Error: VMID must be a number."
    exit 1
fi

# Snippets directory
SNIPPETS_DIR="/var/lib/vz/snippets"

# Check if directory exists
if [ ! -d "$SNIPPETS_DIR" ]; then
    echo "Error: Directory $SNIPPETS_DIR not found!"
    exit 2
fi

cd "$SNIPPETS_DIR" || exit 3

# Create YAML file userconfig-<VMID>.yaml
YAML_FILE="userconfig-${VMID}.yaml"

if [ -f "$YAML_FILE" ]; then
    echo "File $YAML_FILE already exists, skipping creation."
else
    touch "$YAML_FILE"
    echo "Created $YAML_FILE"
fi

# Start the VM
echo "Starting VMID $VMID..."
qm start "$VMID"

# Check start status
if [ $? -eq 0 ]; then
    echo "VM $VMID started successfully!"
else
    echo "Failed to start VM $VMID. Check Proxmox logs for details."
fi
