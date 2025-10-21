#!/bin/bash
# Author: Eisa Mohammadzadhe
# Company: ultahost.com
# Description: 
#   Maintenance script for cleaning up old backups, logs, and LSWS cache.
#   Keeps only the newest backup folder in /backup.
#   Truncates old LSWS log files.
#   Clears LSWS cache data.
#   Finally displays disk usage for the root partition (/).

# ===============================
# Color codes for colorful output
# ===============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===== STARTING MAINTENANCE SCRIPT =====${NC}"

# ==============================================================
# STEP 1: Clean /backup folder, keeping only the newest folder
# ==============================================================
echo -e "${YELLOW}\n[STEP 1] Cleaning /backup folder, keeping only the newest folder${NC}"

# Find the newest folder in /backup based on modification time
keep=$(find /backup -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | head -n1 | awk '{print $2}')

# Check if a folder was found
if [ -z "$keep" ]; then
  echo -e "${RED}No backup folders found in /backup! Skipping cleanup...${NC}"
else
  echo -e "Keeping folder: ${GREEN}$(basename "$keep")${NC}"

  # Remove all other folders except the newest one
  find /backup -mindepth 1 -maxdepth 1 -type d ! -path "$keep" -print -exec rm -rf {} \;

  echo -e "${GREEN}Backup cleanup completed successfully!${NC}"
fi

# ==============================================================
# STEP 2: Truncate LSWS log files (*.log.*)
# ==============================================================
echo -e "${YELLOW}\n[STEP 2] Truncating LSWS log files (*.log.*)${NC}"

# Find and truncate all rotated LSWS log files to 0 bytes
find /usr/local/lsws/logs -type f -name '*.log.*' -print -exec truncate -s 0 {} \;

echo -e "${GREEN}Log truncation completed successfully!${NC}"

# ==============================================================
# STEP 3: Clean LSWS cache data
# ==============================================================
echo -e "${YELLOW}\n[STEP 3] Cleaning LSWS cache data...${NC}"

# Remove all private cache files quietly
find /usr/local/lsws/cachedata/*/priv -mindepth 1 -exec rm -rf {} + 2>/dev/null

echo -e "${GREEN}Cache cleanup completed successfully!${NC}"

# ==============================================================
# STEP 4: Show current disk usage for root (/)
# ==============================================================
echo -e "${YELLOW}\n[STEP 4] Current disk usage for /${NC}"

# Display used and available disk space for the root partition
df -h / | awk 'NR==2 {print "'${BLUE}'" $3 " used, " $4 " available in /'${NC}'"}'

echo -e "${BLUE}\n===== MAINTENANCE SCRIPT COMPLETED =====${NC}"
