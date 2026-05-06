#!/bin/bash

# --- Configuration ---
TOKEN=""
CHAT_ID=""
INSTALL_PATH="/opt/root_monitor.sh"
SERVICE_PATH="/etc/systemd/system/root-monitor.service"

echo "------------------------------------------------"
echo "   Ultahost Root Monitor Installer for cPanel   "
echo "------------------------------------------------"

# 1. Check for existing installation
echo "[+] Checking for existing installation..."

if [ -f "$INSTALL_PATH" ] || [ -f "$SERVICE_PATH" ]; then
    echo "⚠️  ALREADY INSTALLED: The monitoring service is already present on this server."
    echo "    - To reinstall, first run: systemctl stop root-monitor && rm $INSTALL_PATH"
    echo "    - Script aborted to prevent conflicts."
    exit 1
fi

# 2. Create the Monitoring Script
echo "[+] Creating monitoring script at $INSTALL_PATH..."

cat << 'EOF' > $INSTALL_PATH
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
    local geo_display=$(get_geo_info "$ip")
    
    local msg="$header%0A%0A🖥 <b>Server:</b> <code>$SERVER_NAME</code>%0A🌍 <b>Server IP:</b> <code>$SERVER_IP</code>%0A$service_icon <b>Service:</b> <b>$service_name</b>%0A🕵️‍♂️ <b>User IP:</b> <code>$ip</code>%0A$geo_display%0A🕒 <b>Time:</b> <code>$time</code>"
    
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$msg" \
        -d parse_mode="HTML" > /dev/null
}

# 1. Monitor SSH Root Logins
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

# 2. Monitor WHM Root Logins
tail -F /usr/local/cpanel/logs/login_log | while read line; do
    if [[ "$line" == *"root - SUCCESS LOGIN whostmgrd"* ]]; then
        IP=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
        TIME_STR=$(echo "$line" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}")
        send_telegram "🌐 <b>WHM PANEL LOGIN</b>" "🛡" "WHM (Web Dashboard)" "$IP" "$TIME_STR"
    fi
done &

wait
EOF

# 3. Set Permissions
chmod +x $INSTALL_PATH

# 4. Create Systemd Service
echo "[+] Creating systemd service..."

cat << EOF > $SERVICE_PATH
[Unit]
Description=Telegram Alert for SSH and WHM Root Logins
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_PATH
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 5. Enable and Start Service
echo "[+] Starting and enabling service..."
systemctl daemon-reload
systemctl enable root-monitor.service
systemctl restart root-monitor.service

# 6. Final Check and Test Message
if systemctl is-active --quiet root-monitor.service; then
    echo "------------------------------------------------"
    echo "✅ INSTALLATION SUCCESSFUL!"
    echo "------------------------------------------------"
    
    HOSTNAME=$(hostname)
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="✅ <b>New Deployment</b>%0A🖥 <b>Server:</b> <code>$HOSTNAME</code>%0A💡 <i>Monitoring is now active.</i>" \
        -d parse_mode="HTML" > /dev/null
else
    echo "❌ ERROR: Service failed to start."
fi
