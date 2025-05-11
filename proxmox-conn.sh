#!/bin/bash

# Author: Eisa Mohammadzadeh
# Description: Display top 10 IPs with most active connections and their VMID in Proxmox

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
NC="\e[0m"

echo -e "${CYAN}Top 10 IPs with most active connections and their corresponding VMIDs${NC}"
echo -e "${YELLOW}---------------------------------------------------------------${NC}"

# ذخیره خروجی conntrack به صورت فایل موقت
tmpfile=$(mktemp)
conntrack -L 2>/dev/null | grep -oP 'src=\K[0-9.]+' | sort | uniq -c | sort -rn | head -n 10 > "$tmpfile"

# پردازش خروجی از فایل موقت
while read count ip; do
    conf_file=$(grep -rl "$ip" /etc/pve/nodes/*/qemu-server/*.conf 2>/dev/null | head -n 1)

    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        vmid=$(basename "$conf_file" .conf)
        echo -e "${GREEN}$ip${NC} | ${YELLOW}$count connections${NC} | VMID: ${CYAN}$vmid${NC}"
    else
        echo -e "${GREEN}$ip${NC} | ${YELLOW}$count connections${NC} | VMID: ${RED}not found${NC}"
    fi
done < "$tmpfile"

# پاک کردن فایل موقت
rm -f "$tmpfile"
