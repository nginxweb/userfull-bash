#!/bin/bash

BOT_TOKEN="8776917601:AAECdL4bwZS5TCdfMRUURwU0iNzN17CXSmc"
CHAT_ID="992809735"
SCRIPT_PATH="/opt/jetbackup-end.sh"

cat > "$SCRIPT_PATH" << 'SCRIPT'
#!/bin/bash

BOT_TOKEN="8776917601:AAECdL4bwZS5TCdfMRUURwU0iNzN17CXSmc"
CHAT_ID="992809735"

JOB_ID="${1:-Unknown}"
ACCOUNT_ID="${2:-Unknown}"
BACKUP_TYPE="${3:-Unknown}"
EXIT_CODE="${4:-Unknown}"

SERVER_NAME=$(hostname)
CURRENT_DATE=$(date +"%Y-%m-%d")
CURRENT_TIME=$(date +"%H:%M:%S")
TIMEZONE=$(date +"%Z")
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')

if [ "$EXIT_CODE" == "0" ]; then
    STATUS_ICON="✅"
    STATUS_TEXT="Completed Successfully"
else
    STATUS_ICON="❌"
    STATUS_TEXT="Failed (Exit Code: ${EXIT_CODE})"
fi

MESSAGE="${STATUS_ICON} <b>JetBackup Finished</b> ${STATUS_ICON}

<b>Job ID:</b> <code>${JOB_ID}</code>
<b>Account:</b> <code>${ACCOUNT_ID}</code>
<b>Type:</b> <code>${BACKUP_TYPE}</code>

🖥 <b>${SERVER_NAME}</b>
📅 ${CURRENT_DATE} | ⏱️ ${CURRENT_TIME} ${TIMEZONE}
💾 Disk: ${DISK_USAGE}

<b>Status:</b> ${STATUS_TEXT}"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d parse_mode="HTML" \
    --data-urlencode "text=$MESSAGE" \
    -d disable_web_page_preview="true"

exit 0
SCRIPT

chmod +x "$SCRIPT_PATH"
echo "JetBackup hook installed at $SCRIPT_PATH"
bash "$SCRIPT_PATH" "TEST" "TEST" "TEST" "0"
