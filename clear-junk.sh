#!/bin/bash
# Author: Eisa Mohammadzadeh
# Company: ultahost.com
# Description: Maintenance script to clean backups, LSWS logs, and LSWS cache.

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===== STARTING MAINTENANCE SCRIPT =====${NC}"

# -------------------------
# STEP 1: Clean /backup folder, keep newest
# -------------------------
echo -e "${YELLOW}\n[STEP 1] Cleaning /backup folder, keeping only the newest folder${NC}"
keep=$(find /backup -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | head -n1 | awk '{print $2}')
if [ -z "$keep" ]; then
  echo -e "${RED}No backup folders found in /backup! Skipping cleanup...${NC}"
else
  echo -e "Keeping folder: ${GREEN}$(basename "$keep")${NC}"
  find /backup -mindepth 1 -maxdepth 1 -type d ! -path "$keep" -print -exec rm -rf {} \;
  echo -e "${GREEN}Backup cleanup completed successfully!${NC}"
fi

# -------------------------
# STEP 2: Truncate LSWS logs
# -------------------------
echo -e "${YELLOW}\n[STEP 2] Truncating LSWS log files (*.log.*)${NC}"
find /usr/local/lsws/logs -type f -name '*.log.*' -print -exec truncate -s 0 {} \;
echo -e "${GREEN}Log truncation completed successfully!${NC}"

# -------------------------
# STEP 3: Clean LSWS cache
# -------------------------
echo -e "${YELLOW}\n[STEP 3] Cleaning LSWS cache data...${NC}"
rm -rf /usr/local/lsws/cachedata/* 2>/dev/null
echo -e "${GREEN}Cache cleanup completed successfully!${NC}"

# -------------------------
# STEP 4: Show root disk usage
# -------------------------
echo -e "${YELLOW}\n[STEP 4] Current disk usage for /${NC}"
df -h / | awk 'NR==2 {print "'${BLUE}'" $3 " used, " $4 " available in /'${NC}'"}'

echo -e "${BLUE}\n===== MAINTENANCE SCRIPT COMPLETED =====${NC}"
