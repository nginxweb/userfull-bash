#!/bin/bash

# JetBackup Telegram Hook Installer
# This script installs post-backup hook for JetBackup with Telegram notifications

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BOT_TOKEN="8776917601:AAECdL4bwZS5TCdfMRUURwU0iNzN17CXSmc"
CHAT_ID="992809735"
SCRIPT_PATH="/opt/jetbackup-end.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}JetBackup Telegram Hook Installer${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (use sudo)${NC}" 
   exit 1
fi

# Check if JetBackup is installed
if ! command -v jetbackup &> /dev/null && [ ! -d "/usr/local/jetbackup" ]; then
    echo -e "${YELLOW}Warning: JetBackup does not seem to be installed on this system${NC}"
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
echo -e "${GREEN}✓ Hook script created and permissions set${NC}"

# Test the script
echo -e "${GREEN}Testing the hook script...${NC}"
if bash "$SCRIPT_PATH" "TEST_JOB" "TEST_ACCOUNT" "TEST_TYPE" "0"; then
    echo -e "${GREEN}✓ Test notification sent to Telegram!${NC}"
else
    echo -e "${YELLOW}⚠ Test failed. Check curl and network connectivity${NC}"
fi

# Instructions for JetBackup configuration
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Script installed at: ${YELLOW}${SCRIPT_PATH}${NC}"
echo
echo -e "${YELLOW}Next Steps - Configure JetBackup:${NC}"
echo -e "1. Login to WHM → JetBackup"
echo -e "2. Go to 'Settings' → 'Backup Destinations' or 'Jobs'"
echo -e "3. Look for 'Post Backup Script' or 'After Backup Script' option"
echo -e "4. Set the path to: ${GREEN}${SCRIPT_PATH}${NC}"
echo -e "5. Save the configuration"
echo
echo -e "Alternative - For cPanel/WHM JetBackup 5:"
echo -e "  Go to: JetBackup → Settings → Hooks"
echo -e "  Add new hook with type: 'After Backup'"
echo -e "  Command: ${SCRIPT_PATH} %job_id %account %type %exit_code"
echo
echo -e "${GREEN}✓ Hook script is ready to use!${NC}"
