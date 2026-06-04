#!/usr/bin/env bash

# ================= INSTALL SCRIPT =================
# This script installs the LiteSpeed DDoS monitor on the server

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "     LiteSpeed DDoS Monitor - Installation Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ================= CHECK DIRECTORY =================
echo "▶ Checking directory /etc/imunify360..."

if [[ ! -d "/etc/imunify360" ]]; then
    echo -e "\033[0;31m✗ ERROR: Directory /etc/imunify360 does not exist!\033[0m"
    echo "This server does not have Imunify360 installed."
    echo "Installation aborted."
    exit 1
fi

echo -e "\033[0;32m✓ Directory exists\033[0m\n"

# ================= CREATE MAIN SCRIPT =================
echo "▶ Creating attack-eric.sh script..."
cat > /etc/imunify360/attack-eric.sh << 'EOF'
#!/usr/bin/env bash

# ================= CONFIG =================
EXPORTER_URL="http://127.0.0.1:9936/metrics"
REQ_THRESHOLD=15
CONN_THRESHOLD=70
TELEGRAM_BOT_TOKEN="8770766348:AAEcXgiu12B6KSnRzgbwiRe2Ty3sRG8eExk"
TELEGRAM_CHAT_ID="992809735"
LAST_ALERT_FILE="/tmp/litespeed_last_alerts.txt"

HOSTNAME=$(hostname)

TMP_FILE=$(mktemp)
ALERT_FILE=$(mktemp)

# ================= TELEGRAM FUNCTION =================
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${message}" \
        -d parse_mode="HTML" > /dev/null 2>&1
}

# ================= FETCH METRICS =================
DATA=$(curl -s --max-time 5 "$EXPORTER_URL")

if [[ -z "$DATA" ]]; then
    echo "[ERROR] Failed to fetch metrics from exporter"
    exit 1
fi

# ================= PARSE REQUESTS PER SECOND =================
echo "$DATA" | grep litespeed_requests_per_second_per_vhost | while read -r line; do
    VHOST=$(echo "$line" | sed -n 's/.*vhost="\([^"]*\)".*/\1/p')
    VALUE=$(echo "$line" | grep -oE '[0-9]+(\.[0-9]+)?$')
    [[ -z "$VHOST" || -z "$VALUE" ]] && continue
    CLEAN_VHOST=$(echo "$VHOST" | sed 's/^APVH_//')
    echo "$CLEAN_VHOST req $VALUE" >> "$TMP_FILE"
done

# ================= PARSE ACTIVE CONNECTIONS =================
echo "$DATA" | grep litespeed_current_requests_per_vhost | while read -r line; do
    VHOST=$(echo "$line" | sed -n 's/.*vhost="\([^"]*\)".*/\1/p')
    VALUE=$(echo "$line" | grep -oE '[0-9]+(\.[0-9]+)?$')
    [[ -z "$VHOST" || -z "$VALUE" ]] && continue
    CLEAN_VHOST=$(echo "$VHOST" | sed 's/^APVH_//')
    echo "$CLEAN_VHOST conn $VALUE" >> "$TMP_FILE"
done

# ================= CHECK FOR ATTACKS =================
while read -r VHOST; do
    REQ=$(grep "^$VHOST req" "$TMP_FILE" | awk '{print $3}' | head -n1)
    CONN=$(grep "^$VHOST conn" "$TMP_FILE" | awk '{print $3}' | head -n1)
    REQ=${REQ:-0}
    CONN=${CONN:-0}

    # Check if thresholds are exceeded
    if (( $(echo "$REQ > $REQ_THRESHOLD" | bc -l 2>/dev/null || echo "0") )) || (( CONN > CONN_THRESHOLD )); then
        echo "$VHOST|$REQ|$CONN" >> "$ALERT_FILE"
    fi
done < <(awk '{print $1}' "$TMP_FILE" 2>/dev/null | sort -u)

# ================= SEND ALERTS TO TELEGRAM =================
if [[ -s "$ALERT_FILE" ]]; then
    while IFS="|" read -r VHOST REQ CONN; do
        REQ_FORMATTED=$(printf "%.1f" "$REQ" 2>/dev/null || echo "0")
        CONN_FORMATTED=$(printf "%.0f" "$CONN" 2>/dev/null || echo "0")
        SCORE=$(echo "$REQ_FORMATTED * 2 + $CONN_FORMATTED" | bc 2>/dev/null || echo "0")

        # Determine severity
        if (( $(echo "$REQ > 50" | bc -l 2>/dev/null || echo "0") )) || (( CONN > 200 )); then
            SEVERITY="CRITICAL"
            ICON="🔥🔥🔥"
            EMOJI="💀"
        elif (( $(echo "$REQ > 30" | bc -l 2>/dev/null || echo "0") )) || (( CONN > 100 )); then
            SEVERITY="HIGH"
            ICON="⚠️⚠️"
            EMOJI="🚨"
        else
            SEVERITY="MEDIUM"
            ICON="⚠️"
            EMOJI="📢"
        fi

        # Check for duplicate alert
        ALERT_KEY="${VHOST}|${REQ_FORMATTED}|${CONN_FORMATTED}|${SEVERITY}"

        if ! grep -Fxq "$ALERT_KEY" "$LAST_ALERT_FILE" 2>/dev/null; then
            echo "$ALERT_KEY" >> "$LAST_ALERT_FILE"

            MESSAGE="${ICON} <b>DDoS ATTACK DETECTED</b> ${ICON}%0A%0A"
            MESSAGE+="<b>📌 Virtual Host:</b> <code>${VHOST}</code>%0A"
            MESSAGE+="<b>📊 Requests/sec:</b> ${REQ_FORMATTED}%0A"
            MESSAGE+="<b>🔌 Active Connections:</b> ${CONN_FORMATTED}%0A"
            MESSAGE+="<b>🎯 Attack Score:</b> ${SCORE}%0A"
            MESSAGE+="<b>🚨 Severity:</b> <b>${SEVERITY}</b>%0A%0A"
            MESSAGE+="🕒 <code>$(date '+%Y-%m-%d %H:%M:%S')</code>%0A"
            MESSAGE+="🖥️ <b>Server:</b> ${HOSTNAME}"

            send_telegram "$MESSAGE"
        fi
    done < "$ALERT_FILE"

    # Keep only last 100 alerts
    if [[ -f "$LAST_ALERT_FILE" ]]; then
        tail -n 100 "$LAST_ALERT_FILE" > "$LAST_ALERT_FILE.tmp" 2>/dev/null
        mv "$LAST_ALERT_FILE.tmp" "$LAST_ALERT_FILE" 2>/dev/null
    fi
fi

# ================= CLEANUP =================
rm -f "$TMP_FILE" "$ALERT_FILE" 2>/dev/null

exit 0
EOF

echo -e "\033[0;32m✓ Script created\033[0m\n"

# ================= SET PERMISSIONS =================
echo "▶ Setting permissions..."
chmod 755 /etc/imunify360/attack-eric.sh
chown root:root /etc/imunify360/attack-eric.sh
echo -e "\033[0;32m✓ Permissions set (755, root:root)\033[0m\n"

# ================= CHECK DEPENDENCIES =================
echo "▶ Checking dependencies..."

# Check curl
if ! command -v curl &> /dev/null; then
    echo "⚠ curl not found, installing..."
    yum install -y curl
fi

# Check bc
if ! command -v bc &> /dev/null; then
    echo "⚠ bc not found, installing..."
    yum install -y bc
fi

echo -e "\033[0;32m✓ All dependencies satisfied\033[0m\n"

# ================= ADD TO CRON (DIRECT) =================
echo "▶ Adding to /var/spool/cron/root..."

# Create cron directory if not exists
mkdir -p /var/spool/cron

# Remove old entry if exists
if [[ -f /var/spool/cron/root ]]; then
    sed -i '/\/etc\/imunify360\/attack-eric.sh/d' /var/spool/cron/root
fi

# Add new cron job (every minute)
echo "* * * * * /etc/imunify360/attack-eric.sh > /dev/null 2>&1" >> /var/spool/cron/root

# Set proper permissions for cron file
chmod 600 /var/spool/cron/root
chown root:root /var/spool/cron/root

echo -e "\033[0;32m✓ Cron job added to /var/spool/cron/root\033[0m\n"

# ================= TEST RUN =================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Running test..."
echo ""

bash /etc/imunify360/attack-eric.sh

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "\033[0;32m✓ INSTALLATION COMPLETE ✓\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📁 Script location: /etc/imunify360/attack-eric.sh"
echo "🔐 Script permissions: 755 (executable by all, writable only by root)"
echo "⏰ Cron location: /var/spool/cron/root (every minute)"
echo "🔐 Cron permissions: 600"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
