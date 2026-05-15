#!/bin/bash

# ============================================================
# Imunify360 Telegram Alert - Complete Setup Script (Fixed)
# ============================================================
set -e

BOT_TOKEN="8770766348:AAEcXgiu12B6KSnRzgbwiRe2Ty3sRG8eExk"
CHAT_ID="992809735"
PERIOD="900"
SCRIPT_PATH="/etc/imunify360/telegram_malware_alert.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Imunify360 Telegram Alert Setup Script              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

[ "$EUID" -ne 0 ] && echo -e "${RED}Error: Run as root!${NC}" && exit 1

command -v imunify360-agent &> /dev/null || { echo -e "${RED}Error: Imunify360 not installed!${NC}"; exit 1; }
echo -e "${GREEN}✓${NC} Imunify360 detected"

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Installing jq...${NC}"
    command -v yum &> /dev/null && yum install jq -y -q
    command -v apt &> /dev/null && { apt update -qq && apt install jq -y -qq; }
fi
echo -e "${GREEN}✓${NC} jq installed"

# ============================================================
# CREATE ALERT SCRIPT
# ============================================================
echo -e "${YELLOW}Creating alert script...${NC}"

cat > ${SCRIPT_PATH} << 'ALERTEOF'
#!/bin/bash

BOT_TOKEN="BOT_PLACEHOLDER"
CHAT_ID="CHAT_PLACEHOLDER"

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d parse_mode="HTML" \
        -d text="${message}" > /dev/null 2>&1
}

INPUT=$(cat)
EVENT_TYPE=$(echo "$INPUT" | jq -r '.event_id // .event_type // "UNKNOWN"')
EVENTS_TOTAL=$(echo "$INPUT" | jq -r '.events_total // 1')
PERIOD_STARTED=$(echo "$INPUT" | jq -r '.period_started // empty')
SERVER_HOSTNAME=$(hostname)
SERVER_IP=$(hostname -I | awk '{print $1}')

if [ -n "$PERIOD_STARTED" ] && [ "$PERIOD_STARTED" != "null" ]; then
    TIMESTAMP=$(date -d "@${PERIOD_STARTED}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
else
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
fi

USERS=$(echo "$INPUT" | jq -r '[.blocked_scripts[].user] | unique | .[]')
PATHS=$(echo "$INPUT" | jq -r '[.blocked_scripts[].path] | unique | .[]')
RULE_IDS=$(echo "$INPUT" | jq -r '[.blocked_scripts[].rule_id] | unique | join(", ")')

declare -A USER_BLOCKS
while IFS= read -r user; do
    count=$(echo "$INPUT" | jq -r "[.blocked_scripts[] | select(.user == \"${user}\")] | length")
    USER_BLOCKS["$user"]=$count
done < <(echo "$USERS")

USER_STATS=""
while IFS= read -r user; do
    if [ -n "$user" ]; then
        USER_STATS="${USER_STATS}  • <code>${user}</code>: ${USER_BLOCKS[$user]} blocks
"
    fi
done < <(echo "$USERS")

PATHS_FORMATTED=""
while IFS= read -r path; do
    if [ -n "$path" ]; then
        PATHS_FORMATTED="${PATHS_FORMATTED}<code>${path}</code>
"
    fi
done < <(echo "$PATHS")

MESSAGE="<b>🚫 Proactive Defense - Script Blocked</b>

🖥️ <b>Server:</b> <code>${SERVER_HOSTNAME}</code> (${SERVER_IP})
🕐 <b>Time:</b> <code>${TIMESTAMP}</code>
🛡️ <b>Rule IDs:</b> <code>${RULE_IDS}</code>

📊 <b>Total Blocks:</b> <code>${EVENTS_TOTAL}</code>

👤 <b>Affected Users:</b>
${USER_STATS}
📁 <b>Blocked Scripts:</b>
${PATHS_FORMATTED}
<i>🔐 Imunify360 Notification System</i>"

send_telegram "$MESSAGE"
exit 0
ALERTEOF

sed -i "s|BOT_PLACEHOLDER|${BOT_TOKEN}|g" ${SCRIPT_PATH}
sed -i "s|CHAT_PLACEHOLDER|${CHAT_ID}|g" ${SCRIPT_PATH}

chown root:_imunify ${SCRIPT_PATH}
chmod g+x ${SCRIPT_PATH}
echo -e "${GREEN}✓${NC} Script created: ${SCRIPT_PATH}"

# ============================================================
# CONFIGURE NOTIFICATIONS
# ============================================================
echo -e "${YELLOW}Configuring Imunify360 notifications...${NC}"

imunify360-agent notifications-config update \
    "{\"rules\": { \
        \"SCRIPT_BLOCKED\": {\"SCRIPT\": {\"scripts\": [\"${SCRIPT_PATH}\"], \"enabled\": true, \"period\": ${PERIOD}}}, \
        \"REALTIME_MALWARE_FOUND\": {\"SCRIPT\": {\"scripts\": [\"${SCRIPT_PATH}\"], \"enabled\": true, \"period\": ${PERIOD}}}, \
        \"CUSTOM_SCAN_MALWARE_FOUND\": {\"SCRIPT\": {\"scripts\": [\"${SCRIPT_PATH}\"], \"enabled\": true}} \
      }}"

systemctl restart imunify-notifier
echo -e "${GREEN}✓${NC} Notifications configured & service restarted"

# ============================================================
# TEST
# ============================================================
echo -e "${YELLOW}Testing notification...${NC}"

TEST_JSON='{"blocked_scripts":[{"domain":"","path":"/home/testuser/public_html/test.php","rule_id":99999,"user":"testuser"}],"event_id":"SCRIPT_BLOCKED","events_total":1,"period_started":'$(date +%s)'}'
echo "$TEST_JSON" | ${SCRIPT_PATH} && echo -e "${GREEN}✓${NC} Test sent!" || echo -e "${RED}✗${NC} Test failed"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✅ Setup Complete!                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo -e "Script : ${SCRIPT_PATH}"
echo -e "Period : ${PERIOD}s (15 min)"
echo -e "Events : SCRIPT_BLOCKED + REALTIME_MALWARE_FOUND + CUSTOM_SCAN_MALWARE_FOUND"
