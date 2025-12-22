#!/bin/bash
# Author: Eisa Mohammadzadeh
# Company: ultahost.com
# Description: Maintenance script to clean backups, LSWS logs, LSWS cache, large system logs, and journalctl logs.

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
# STEP 4: Find and truncate large log files in /var/log
# -------------------------
echo -e "${YELLOW}\n[STEP 4] Finding and truncating large log files (>20MB) in /var/log${NC}"

large_logs=$(find /var/log -type f -size +20M 2>/dev/null)

if [ -z "$large_logs" ]; then
  echo -e "${GREEN}No log files larger than 20MB found in /var/log${NC}"
else
  echo -e "${BLUE}Large log files found:${NC}"
  find /var/log -type f -size +20M -exec ls -lh {} \; 2>/dev/null
  
  file_count=$(echo "$large_logs" | wc -l)
  echo -e "${YELLOW}Truncating $file_count large log file(s)...${NC}"
  
  find /var/log -type f -size +20M -exec truncate -s 0 {} \; 2>/dev/null
  echo -e "${GREEN}Large log files have been truncated successfully!${NC}"
fi

# -------------------------
# STEP 5: Clean journalctl logs
# -------------------------
echo -e "${YELLOW}\n[STEP 5] Rotating and vacuuming journalctl logs${NC}"

journalctl --rotate
journalctl --vacuum-time=1s

echo -e "${GREEN}journalctl logs cleaned successfully!${NC}"

# -------------------------
# STEP 6: Show root disk usage
# -------------------------
echo -e "${YELLOW}\n[STEP 6] Current disk usage for /${NC}"
df -h / | awk 'NR==2 {print "'${BLUE}'" $3 " used, " $4 " available in /'${NC}'"}'

echo -e "${BLUE}\n===== MAINTENANCE SCRIPT COMPLETED =====${NC}"
