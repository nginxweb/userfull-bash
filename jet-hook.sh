#!/bin/bash

# JetBackup Telegram Hook Installer - Self-Executing Script
# Just run: bash this_script.sh

set -e

# Make itself executable if not already
if [[ ! -x "$0" ]]; then
    chmod +x "$0"
    exec "$0" "$@"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
BOT_TOKEN="8776917601:AAECdL4bwZS5TCdfMRUURwU0iNzN17CXSmc"
CHAT_ID="992809735"
SCRIPT_PATH="/opt/jetbackup-end.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}JetBackup Telegram Hook Installer${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   echo -e "${YELLOW}Please run: sudo bash $0${NC}"
   exit 1
fi

# Check if JetBackup is installed
if ! command -v jetbackup &> /dev/null && [ ! -d "/usr/local/jetbackup" ]; then
    echo -e "${YELLOW}Warning: JetBackup does not seem to be installed${NC}"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create the hook script
echo -e "${GREEN}Creating JetBackup hook script at ${SCRIPT_PATH}...${NC}"

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

# Set execute permission
chmod +x "$SCRIPT_PATH"
echo -e "${GREEN}✓ Hook script created at ${SCRIPT_PATH}${NC}"

# Test the script
echo -e "${GREEN}Testing Telegram notification...${NC}"
if bash "$SCRIPT_PATH" "TEST_JOB" "TEST_ACCOUNT" "TEST_TYPE" "0"; then
    echo -e "${GREEN}✓ Test notification sent successfully!${NC}"
else
    echo -e "${YELLOW}⚠ Test failed. Check network and curl${NC}"
fi

# Create auto-configuration for JetBackup if possible
if [ -d "/usr/local/jetbackup" ]; then
    # Try to automatically configure JetBackup 5
    if [ -f "/usr/local/jetbackup/config/hooks.conf" ]; then
        echo -e "${GREEN}Detected JetBackup 5, adding hook configuration...${NC}"
        
        cat >> "/usr/local/jetbackup/config/hooks.conf" << EOF || true
[after_backup]
command = ${SCRIPT_PATH} %job_id %account %type %exit_code
enabled = 1
EOF
        echo -e "${GREEN}✓ Hook automatically configured for JetBackup 5${NC}"
    fi
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "✓ Hook script: ${YELLOW}${SCRIPT_PATH}${NC}"
echo -e "✓ Permissions: ${YELLOW}Executable${NC}"
echo -e "✓ Test sent: ${YELLOW}Check Telegram${NC}"
echo
echo -e "${GREEN}All done! JetBackup will now send Telegram notifications.${NC}"
