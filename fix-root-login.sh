#!/bin/bash

# ============================================
# Script: update_root_monitor.sh
# Purpose: Replace /opt/root_monitor.sh with new version
#          that skips Telegram alerts for specific IPs
# ============================================

echo "=============================================="
echo "  Updating root-monitor Service with IP Skip"
echo "=============================================="
echo ""

# Backup current file
if [ -f /opt/root_monitor.sh ]; then
    echo "📦 Creating backup: /opt/root_monitor.sh.bak"
    cp /opt/root_monitor.sh /opt/root_monitor.sh.bak.$(date +%Y%m%d_%H%M%S)
fi

# Write new file
cat > /opt/root_monitor.sh << 'EOF'
#!/bin/bash

# Telegram Bot Configuration
TOKEN="8770766348:AAEcXgiu12B6KSnRzgbwiRe2Ty3sRG8eExk"
CHAT_ID="992809735"

# Server Info
SERVER_NAME=$(hostname)
SERVER_IP=$(curl -s --max-time 5 ifconfig.me || echo "Unknown")

# Variables for SSH Deduplication
LAST_SSH_IP=""
LAST_SSH_TIME=0

# ============================================
# List of IPs to ignore (Telegram alerts will be skipped for these IPs)
# ============================================
SKIP_IPS=("84.200.40.124")

# Function to check if IP should be skipped
should_skip_ip() {
    local ip="$1"
    for skip_ip in "${SKIP_IPS[@]}"; do
        if [[ "$ip" == "$skip_ip" ]]; then
            return 0  # true, skip this IP
        fi
    done
    return 1  # false, don't skip
}

# Function to get Geo Location
get_geo_info() {
    local ip=$1
    local geo=$(curl -s --max-time 5 "http://ip-api.com/line/$ip?fields=country,countryCode")
    if [ ! -z "$geo" ]; then
        local country=$(echo "$geo" | sed -n '1p')
        local code=$(echo "$geo" | sed -n '2p')
        echo "📍 <b>Location:</b> $country ($code)"
    else
        echo "📍 <b>Location:</b> Unknown"
    fi
}

# Function to send Telegram message
send_telegram() {
    local header="$1"
    local service_icon="$2"
    local service_name="$3"
    local ip="$4"
    local time="$5"

    # Skip if IP is in the ignore list
    if should_skip_ip "$ip"; then
        echo "[$(date)] Skipping notification for IP: $ip"
        return 0
    fi

    local geo_display=$(get_geo_info "$ip")

    local msg="$header%0A%0A🖥 <b>Server:</b> <code>$SERVER_NAME</code>%0A🌍 <b>Server IP:</b> <code>$SERVER_IP</code>%0A$service_icon <b>Service:</b> <b>$service_name</b>%0A🕵️‍♂️ <b>User IP:</b> <code>$ip</code>%0A$geo_display%0A🕒 <b>Time:</b> <code>$time</code>"

    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$msg" \
        -d parse_mode="HTML" > /dev/null
}

# ============================================
# 1. Monitor SSH Root Logins
# ============================================
tail -F /var/log/secure | while read line; do
    if [[ "$line" == *"Accepted password for root"* ]] || [[ "$line" == *"Accepted publickey for root"* ]]; then
        CURRENT_IP=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - LAST_SSH_TIME))
        if [[ "$CURRENT_IP" != "$LAST_SSH_IP" ]] || [[ $TIME_DIFF -gt 5 ]]; then
            TIME_STR=$(echo "$line" | awk '{print $1, $2, $3}')
            send_telegram "💻 <b>SSH TERMINAL ACCESS</b>" "🛠" "SSH (Console)" "$CURRENT_IP" "$TIME_STR"
            LAST_SSH_IP="$CURRENT_IP"
            LAST_SSH_TIME=$CURRENT_TIME
        fi
    fi
done &

# ============================================
# 2. Monitor WHM Root Logins
# ============================================
tail -F /usr/local/cpanel/logs/login_log | while read line; do
    if [[ "$line" == *"root - SUCCESS LOGIN whostmgrd"* ]]; then
        IP=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
        TIME_STR=$(echo "$line" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}")
        send_telegram "🌐 <b>WHM PANEL LOGIN</b>" "🛡" "WHM (Web Dashboard)" "$IP" "$TIME_STR"
    fi
done &

wait
EOF

# Set execute permission
chmod +x /opt/root_monitor.sh

# Reload systemd and restart service
echo "🔄 Reloading systemd..."
systemctl daemon-reload

echo "🔄 Restarting root-monitor service..."
systemctl restart root-monitor.service

# Check status
echo ""
echo "=============================================="
echo "  Service Status"
echo "=============================================="
systemctl status root-monitor.service --no-pager

echo ""
echo "=============================================="
echo "  ✅ Update Complete!"
echo "=============================================="
echo "📌 IPs that will be SKIPPED: 84.200.40.124"
echo "📌 To add more IPs, edit SKIP_IPS array in /opt/root_monitor.sh"
echo "📌 Backup saved in: /opt/root_monitor.sh.bak.*"
echo "=============================================="
EOF

# ============================================
# Make this script executable
# ============================================
chmod +x /root/update_root_monitor.sh

echo ""
echo "✅ Script created: /root/update_root_monitor.sh"
echo ""
echo "To run: /root/update_root_monitor.sh"
echo "=============================================="
