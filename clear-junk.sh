#!/bin/bash
# Author: Eisa Mohammadzadhe
# Company: ultahost.com
# Description: Maintenance script for backup, logs, and LSWS cache cleanup
#              Provides colorful output and shows affected files/folders
#              Finally displays disk usage for /

# Colors for colorful output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===== STARTING MAINTENANCE SCRIPT =====${NC}"

# Step 1: Clean /backup folder except the newest folder ~7 days old
echo -e "${YELLOW}\n[STEP 1] Cleaning /backup folder, keeping the newest folder ~7 days old${NC}"
keep=$(find /backup -maxdepth 1 -type d -mtime +6 | sort | tail -n 1)
echo -e "Keeping folder: ${GREEN}$(basename "$keep")${NC}"

# Remove everything except the folder to keep, show each removed item
find /backup -mindepth 1 -not -name "$(basename "$keep")" -print -exec rm -rf {} \;
echo -e "${GREEN}Backup cleanup completed!${NC}"

# Step 2: Truncate LSWS log files (*.log.*)
echo -e "${YELLOW}\n[STEP 2] Truncating LSWS log files (*.log.*)${NC}"
# Show each log file being truncated
find /usr/local/lsws/logs -type f -name '*.log.*' -print -exec truncate -s 0 {} \;
echo -e "${GREEN}Log truncation completed!${NC}"

# Step 3: Clean LSWS cache data
echo -e "${YELLOW}\n[STEP 3] Cleaning LSWS cache data${NC}"
# Remove all files/folders inside each priv folder, suppress errors
find /usr/local/lsws/cachedata/*/priv -mindepth 1 -print -exec rm -rf {} + 2>/dev/null
echo -e "${GREEN}Cache cleanup completed!${NC}"

# Step 4: Show current disk usage for /
echo -e "${YELLOW}\n[STEP 4] Current disk usage for /${NC}"
du -sh / | awk '{print "'${BLUE}'" $1 "'${NC}' used in /"}'

echo -e "${BLUE}\n===== MAINTENANCE SCRIPT COMPLETED =====${NC}"
