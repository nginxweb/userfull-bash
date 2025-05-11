#!/bin/bash

echo "Top 10 IPs with most connections and their corresponding VMIDs:"
echo "---------------------------------------------------------------"

conntrack -L | grep -oP 'src=\K[0-9.]+' | sort | uniq -c | sort -rn | head -n 10 | while read count ip; do
    vmid=$(grep -rl "$ip" /etc/pve/nodes/*/qemu-server/*.conf | sed -n 's/.*\/\([0-9]\+\)\.conf/\1/p')
    echo "$ip | $count connections | VMID: ${vmid:-not found}"
done
