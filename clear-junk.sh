#!/bin/bash
# Author: Eisa Mohammadzadeh
# Company: ultahost.com
# Description: Maintenance script to clean backups, LSWS logs, LSWS cache, large system logs, and journalctl logs.

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Variables for summary report
TOTAL_SPACE_FREED=0
SPACE_FREED_STEP1=0
SPACE_FREED_STEP2=0
SPACE_FREED_STEP3=0
SPACE_FREED_STEP4=0
SPACE_FREED_STEP5=0

# Temporary file for logging (will be removed at the end)
TEMP_LOG=$(mktemp /tmp/maintenance_log.XXXXXX)

# Function to get available disk space in KB
get_available_space() {
    df -k / | awk 'NR==2 {print $4}'
}

# Function to convert KB to human readable format
human_readable() {
    local size_kb=$1
    if [ $size_kb -ge 1048576 ]; then
        printf "%.2f GB" $(echo "scale=2; $size_kb/1048576" | bc)
    elif [ $size_kb -ge 1024 ]; then
        printf "%.2f MB" $(echo "scale=2; $size_kb/1024" | bc)
    else
        printf "%d KB" $size_kb
    fi
}

# Function to calculate freed space
calculate_freed_space() {
    local before=$1
    local after=$2
    echo $((before - after))
}

# Function to print separator
print_separator() {
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
}

# Function to print header
print_header() {
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                 ULTRAHOST MAINTENANCE SCRIPT                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${CYAN}📅 Start Time: $(date)${NC}"
    echo -e "${CYAN}🖥️  Server: $(hostname)${NC}"
    print_separator
}

# Function to print footer
print_footer() {
    print_separator
    echo -e "${GREEN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║          ✅ MAINTENANCE COMPLETED SUCCESSFULLY!               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${CYAN}⏰ End Time: $(date)${NC}"
    print_separator
}

# Function to print step header
print_step_header() {
    echo -e "\n${BLUE}${BOLD}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}${BOLD}│ STEP $1: $2${NC}"
    echo -e "${BLUE}${BOLD}└────────────────────────────────────────────────────────────┘${NC}"
}

# Function to print summary table
print_summary_table() {
    echo -e "\n${GREEN}${BOLD}📊 DISK SPACE SUMMARY${NC}"
    echo -e "${YELLOW}┌────────────────────────────────────────────────────────────┐${NC}"
    
    # Calculate column widths
    col1=30
    col2=20
    
    printf "${CYAN}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Initial Available Space:" "$(human_readable $INITIAL_SPACE)"
    printf "${CYAN}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Final Available Space:" "$(human_readable $FINAL_SPACE)"
    printf "${CYAN}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Total Space Freed:" "$(human_readable $TOTAL_SPACE_FREED)"
    
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
}

# Function to print steps table
print_steps_table() {
    echo -e "\n${GREEN}${BOLD}🔧 MAINTENANCE STEPS DETAILS${NC}"
    echo -e "${YELLOW}┌────────────────────────────────────────────────────────────┐${NC}"
    
    col1=35
    col2=20
    
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Backup Cleanup" "$(human_readable $SPACE_FREED_STEP1)"
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "LSWS Logs Truncation" "$(human_readable $SPACE_FREED_STEP2)"
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "LSWS Cache Cleanup" "$(human_readable $SPACE_FREED_STEP3)"
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Large Logs Truncation" "$(human_readable $SPACE_FREED_STEP4)"
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Journal Logs Cleanup" "$(human_readable $SPACE_FREED_STEP5)"
    
    echo -e "${YELLOW}├────────────────────────────────────────────────────────────┤${NC}"
    
    TOTAL_FROM_STEPS=$((SPACE_FREED_STEP1 + SPACE_FREED_STEP2 + SPACE_FREED_STEP3 + SPACE_FREED_STEP4 + SPACE_FREED_STEP5))
    printf "${GREEN}${BOLD}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "TOTAL FREED SPACE:" "$(human_readable $TOTAL_FROM_STEPS)"
    
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
}

# Function to print improvement
print_improvement() {
    if [ $INITIAL_SPACE -gt 0 ]; then
        percentage_increase=$(echo "scale=2; ($TOTAL_SPACE_FREED * 100) / $INITIAL_SPACE" | bc)
        echo -e "\n${GREEN}${BOLD}📈 SPACE USAGE IMPROVEMENT${NC}"
        echo -e "${YELLOW}┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}Available space increased by:${NC} ${GREEN}${BOLD}$percentage_increase%${NC}"
        echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
    fi
}

# Trap to clean up temp files on exit
cleanup() {
    echo -e "\n${YELLOW}🧹 Cleaning up temporary files...${NC}"
    if [ -f "$TEMP_LOG" ]; then
        rm -f "$TEMP_LOG"
        echo -e "${GREEN}✓ Temporary log file removed${NC}"
    fi
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

trap cleanup EXIT

# Start execution
print_header

# Get initial disk space
INITIAL_SPACE=$(get_available_space)
echo -e "${YELLOW}📦 Initial Disk Space:${NC} ${GREEN}$(human_readable $INITIAL_SPACE)${NC}"

# -------------------------
# STEP 1: Clean /backup folder, keep newest
# -------------------------
print_step_header "1" "Backup Folder Cleanup"
SPACE_BEFORE_STEP1=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $SPACE_BEFORE_STEP1)${NC}"

keep=$(find /backup -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | awk '{print $2}')
if [ -z "$keep" ]; then
  echo -e "${YELLOW}⚠️ No backup folders found in /backup${NC}"
  SPACE_FREED_STEP1=0
else
  echo -e "${GREEN}✓ Keeping folder: $(basename "$keep")${NC}"
  
  # Calculate and show what will be removed
  echo -e "${CYAN}Removing old backups:${NC}"
  total_size=0
  while IFS= read -r folder; do
    if [ -n "$folder" ] && [ "$folder" != "$keep" ] && [ -d "$folder" ]; then
      size=$(du -sk "$folder" 2>/dev/null | awk '{print $1}')
      total_size=$((total_size + size))
      echo -e "  ${RED}🗑️  $(basename "$folder")${NC} (${YELLOW}$(human_readable $size)${NC})"
    fi
  done < <(find /backup -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  
  if [ $total_size -gt 0 ]; then
    echo -e "${CYAN}Total to remove: $(human_readable $total_size)${NC}"
  fi
  
  # Remove old backups
  find /backup -mindepth 1 -maxdepth 1 -type d ! -path "$keep" -exec rm -rf {} \; 2>/dev/null
  
  SPACE_AFTER_STEP1=$(get_available_space)
  SPACE_FREED_STEP1=$(calculate_freed_space $SPACE_BEFORE_STEP1 $SPACE_AFTER_STEP1)
  echo -e "${GREEN}✅ Freed: $(human_readable $SPACE_FREED_STEP1)${NC}"
fi

# -------------------------
# STEP 2: Truncate LSWS logs
# -------------------------
print_step_header "2" "LSWS Logs Truncation"
SPACE_BEFORE_STEP2=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $SPACE_BEFORE_STEP2)${NC}"

# Get total size of LSWS logs before truncation
lsws_logs_size=0
if [ -d "/usr/local/lsws/logs" ]; then
  lsws_logs_size=$(find /usr/local/lsws/logs -type f -name '*.log.*' -exec du -ck {} + 2>/dev/null | tail -n1 | awk '{print $1}')
  if [ -z "$lsws_logs_size" ]; then
    lsws_logs_size=0
  fi
fi

echo -e "${CYAN}LSWS logs size: $(human_readable $lsws_logs_size)${NC}"

# Truncate the logs
find /usr/local/lsws/logs -type f -name '*.log.*' -exec truncate -s 0 {} \; 2>/dev/null
echo -e "${GREEN}✓ Logs truncated${NC}"

SPACE_AFTER_STEP2=$(get_available_space)
SPACE_FREED_STEP2=$(calculate_freed_space $SPACE_BEFORE_STEP2 $SPACE_AFTER_STEP2)
echo -e "${GREEN}✅ Freed: $(human_readable $SPACE_FREED_STEP2)${NC}"

# -------------------------
# STEP 3: Clean LSWS cache
# -------------------------
print_step_header "3" "LSWS Cache Cleanup"
SPACE_BEFORE_STEP3=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $SPACE_BEFORE_STEP3)${NC}"

# Get cache size before cleanup
cache_size=0
if [ -d "/usr/local/lsws/cachedata" ]; then
  cache_size=$(du -sk /usr/local/lsws/cachedata 2>/dev/null | awk '{print $1}')
  if [ -z "$cache_size" ]; then
    cache_size=0
  fi
fi

echo -e "${CYAN}Cache size: $(human_readable $cache_size)${NC}"

# Clean cache
rm -rf /usr/local/lsws/cachedata/* 2>/dev/null
echo -e "${GREEN}✓ Cache cleaned${NC}"

SPACE_AFTER_STEP3=$(get_available_space)
SPACE_FREED_STEP3=$(calculate_freed_space $SPACE_BEFORE_STEP3 $SPACE_AFTER_STEP3)
echo -e "${GREEN}✅ Freed: $(human_readable $SPACE_FREED_STEP3)${NC}"

# -------------------------
# STEP 4: Find and truncate large log files in /var/log
# -------------------------
print_step_header "4" "Large Log Files Truncation"
SPACE_BEFORE_STEP4=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $SPACE_BEFORE_STEP4)${NC}"

large_logs=$(find /var/log -type f -size +20M 2>/dev/null)
file_count=$(echo "$large_logs" | wc -l)

if [ $file_count -eq 0 ] || [ -z "$large_logs" ]; then
  echo -e "${YELLOW}⚠️ No log files larger than 20MB found${NC}"
  SPACE_FREED_STEP4=0
else
  echo -e "${CYAN}Found ${YELLOW}$file_count${CYAN} large log file(s):${NC}"
  
  # Calculate total size of large logs
  total_large_logs_size=0
  file_counter=1
  while IFS= read -r logfile; do
    if [ -f "$logfile" ]; then
      size=$(du -k "$logfile" 2>/dev/null | awk '{print $1}')
      total_large_logs_size=$((total_large_logs_size + size))
      filename=$(basename "$logfile")
      echo -e "  ${RED}${file_counter}.${NC} ${filename} (${YELLOW}$(human_readable $size)${NC})"
      file_counter=$((file_counter + 1))
    fi
  done <<< "$large_logs"
  
  echo -e "${CYAN}Total size: $(human_readable $total_large_logs_size)${NC}"
  
  # Truncate the logs
  find /var/log -type f -size +20M -exec truncate -s 0 {} \; 2>/dev/null
  echo -e "${GREEN}✓ Large logs truncated${NC}"
  
  SPACE_AFTER_STEP4=$(get_available_space)
  SPACE_FREED_STEP4=$(calculate_freed_space $SPACE_BEFORE_STEP4 $SPACE_AFTER_STEP4)
  echo -e "${GREEN}✅ Freed: $(human_readable $SPACE_FREED_STEP4)${NC}"
fi

# -------------------------
# STEP 5: Clean journalctl logs
# -------------------------
print_step_header "5" "Journal Logs Cleanup"
SPACE_BEFORE_STEP5=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $SPACE_BEFORE_STEP5)${NC}"

# Get journal size before cleanup
journal_size_before=$(journalctl --disk-usage 2>/dev/null | awk '{print $1}' | sed 's/[^0-9]*//g')
if [ -z "$journal_size_before" ]; then
  journal_size_before=0
  echo -e "${YELLOW}⚠️ Unable to get journal size${NC}"
else
  echo -e "${CYAN}Journal size: $(human_readable $journal_size_before)${NC}"
fi

# Clean journal
echo -e "${CYAN}Cleaning journal logs...${NC}"
journalctl --rotate 2>/dev/null
journalctl --vacuum-time=1s 2>/dev/null
echo -e "${GREEN}✓ Journal cleaned${NC}"

SPACE_AFTER_STEP5=$(get_available_space)
SPACE_FREED_STEP5=$(calculate_freed_space $SPACE_BEFORE_STEP5 $SPACE_AFTER_STEP5)
echo -e "${GREEN}✅ Freed: $(human_readable $SPACE_FREED_STEP5)${NC}"

# -------------------------
# FINAL SUMMARY
# -------------------------
print_separator
echo -e "${BLUE}${BOLD}📋 FINAL MAINTENANCE REPORT${NC}"
print_separator

# Get final disk space
FINAL_SPACE=$(get_available_space)
TOTAL_SPACE_FREED=$(calculate_freed_space $INITIAL_SPACE $FINAL_SPACE)

# Print summary tables
print_summary_table
print_steps_table
print_improvement

# Print final message
echo -e "\n${GREEN}${BOLD}🎯 MAINTENANCE RESULTS:${NC}"
if [ $TOTAL_SPACE_FREED -gt 1048576 ]; then
    echo -e "${GREEN}✅ Excellent! Freed over 1 GB of disk space${NC}"
elif [ $TOTAL_SPACE_FREED -gt 512000 ]; then
    echo -e "${GREEN}✅ Good job! Freed significant disk space${NC}"
elif [ $TOTAL_SPACE_FREED -gt 0 ]; then
    echo -e "${GREEN}✅ Some space was freed${NC}"
else
    echo -e "${YELLOW}⚠️ No significant space was freed${NC}"
fi

print_footer
