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
INITIAL_SPACE=0
FINAL_SPACE=0
TOTAL_SPACE_FREED=0
declare -A STEP_SPACE_FREED
STEP_SPACE_FREED[1]=0
STEP_SPACE_FREED[2]=0
STEP_SPACE_FREED[3]=0
STEP_SPACE_FREED[4]=0
STEP_SPACE_FREED[5]=0

# Function to get available disk space in KB
get_available_space() {
    df -k / | awk 'NR==2 {print $4}'
}

# Function to convert KB to human readable format
human_readable() {
    local size_kb=$1
    # Handle negative values
    local sign=""
    if [ $size_kb -lt 0 ]; then
        sign="-"
        size_kb=$((size_kb * -1))
    fi
    
    if [ $size_kb -ge 1048576 ]; then
        printf "%s%.2f GB" "$sign" $(echo "scale=2; $size_kb/1048576" | bc)
    elif [ $size_kb -ge 1024 ]; then
        printf "%s%.2f MB" "$sign" $(echo "scale=2; $size_kb/1024" | bc)
    else
        printf "%s%d KB" "$sign" $size_kb
    fi
}

# Function to calculate space before and after a step
measure_step_space() {
    local step_num=$1
    local before=$2
    local after=$3
    
    # Space freed = after - before (positive means more space available)
    local freed=$((after - before))
    STEP_SPACE_FREED[$step_num]=$freed
    
    echo "$freed"
}

# Function to print separator
print_separator() {
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
}

# Function to print header
print_header() {
    clear
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
    col1=25
    col2=25
    
    printf "${CYAN}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Initial Available Space:" "$(human_readable $INITIAL_SPACE)"
    printf "${CYAN}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Final Available Space:" "$(human_readable $FINAL_SPACE)"
    printf "${CYAN}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Total Space Freed:" "$(human_readable $TOTAL_SPACE_FREED)"
    
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
}

# Function to print steps table
print_steps_table() {
    echo -e "\n${GREEN}${BOLD}🔧 MAINTENANCE STEPS DETAILS${NC}"
    echo -e "${YELLOW}┌────────────────────────────────────────────────────────────┐${NC}"
    
    col1=30
    col2=20
    
    # Calculate total from all steps (should be positive)
    local total_from_steps=0
    for i in {1..5}; do
        total_from_steps=$((total_from_steps + STEP_SPACE_FREED[$i]))
    done
    
    # Make sure total is positive (absolute value)
    if [ $total_from_steps -lt 0 ]; then
        total_from_steps=$((total_from_steps * -1))
    fi
    
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Backup Cleanup" "$(human_readable ${STEP_SPACE_FREED[1]})"
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "LSWS Logs Truncation" "$(human_readable ${STEP_SPACE_FREED[2]})"
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "LSWS Cache Cleanup" "$(human_readable ${STEP_SPACE_FREED[3]})"
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Large Logs Truncation" "$(human_readable ${STEP_SPACE_FREED[4]})"
    printf "${BLUE}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "Journal Logs Cleanup" "$(human_readable ${STEP_SPACE_FREED[5]})"
    
    echo -e "${YELLOW}├────────────────────────────────────────────────────────────┤${NC}"
    printf "${GREEN}${BOLD}%-${col1}s${NC} ${GREEN}%${col2}s${NC}\n" "TOTAL FREED SPACE:" "$(human_readable $total_from_steps)"
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
}

# Function to print improvement
print_improvement() {
    if [ $INITIAL_SPACE -gt 0 ]; then
        # Make sure TOTAL_SPACE_FREED is positive
        local space_freed_positive=$TOTAL_SPACE_FREED
        if [ $space_freed_positive -lt 0 ]; then
            space_freed_positive=$((space_freed_positive * -1))
        fi
        
        percentage_increase=$(echo "scale=2; ($space_freed_positive * 100) / $INITIAL_SPACE" | bc)
        
        echo -e "\n${GREEN}${BOLD}📈 SPACE USAGE IMPROVEMENT${NC}"
        echo -e "${YELLOW}┌────────────────────────────────────────────────────────────┐${NC}"
        
        if [ $TOTAL_SPACE_FREED -gt 0 ]; then
            echo -e "${CYAN}Available space increased by:${NC} ${GREEN}${BOLD}$percentage_increase%${NC}"
        elif [ $TOTAL_SPACE_FREED -lt 0 ]; then
            echo -e "${CYAN}Available space decreased by:${NC} ${RED}${BOLD}$percentage_increase%${NC}"
        else
            echo -e "${CYAN}Available space unchanged${NC}"
        fi
        
        echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
    fi
}

# Start execution
print_header

# Get initial disk space
INITIAL_SPACE=$(get_available_space)
echo -e "${YELLOW}📦 Initial Disk Space:${NC} ${GREEN}$(human_readable $INITIAL_SPACE)${NC}"

# -------------------------
# STEP 1: Clean /backup folder, keep newest
# -------------------------
print_step_header "1" "Backup Folder Cleanup"
STEP1_BEFORE=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $STEP1_BEFORE)${NC}"

keep=$(find /backup -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | awk '{print $2}')
if [ -z "$keep" ]; then
  echo -e "${YELLOW}⚠️ No backup folders found in /backup${NC}"
else
  echo -e "${GREEN}✓ Keeping folder: $(basename "$keep")${NC}"
  
  # Calculate total size of folders to be removed
  total_size=0
  echo -e "${CYAN}Removing old backups:${NC}"
  while IFS= read -r folder; do
    if [ -n "$folder" ] && [ "$folder" != "$keep" ] && [ -d "$folder" ]; then
      size=$(du -sk "$folder" 2>/dev/null | awk '{print $1}')
      if [ -n "$size" ]; then
        total_size=$((total_size + size))
        echo -e "  ${RED}🗑️  $(basename "$folder")${NC} (${YELLOW}$(human_readable $size)${NC})"
      fi
    fi
  done < <(find /backup -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  
  if [ $total_size -gt 0 ]; then
    echo -e "${CYAN}Total to remove: $(human_readable $total_size)${NC}"
  fi
  
  # Remove old backups
  find /backup -mindepth 1 -maxdepth 1 -type d ! -path "$keep" -exec rm -rf {} \; 2>/dev/null
fi

# Wait a moment for disk operations to complete
sleep 2
STEP1_AFTER=$(get_available_space)
STEP_SPACE_FREED[1]=$(measure_step_space 1 $STEP1_BEFORE $STEP1_AFTER)

echo -e "${CYAN}Space after: $(human_readable $STEP1_AFTER)${NC}"
if [ ${STEP_SPACE_FREED[1]} -gt 0 ]; then
    echo -e "${GREEN}✅ Freed: $(human_readable ${STEP_SPACE_FREED[1]})${NC}"
elif [ ${STEP_SPACE_FREED[1]} -lt 0 ]; then
    echo -e "${RED}⚠️ Lost: $(human_readable ${STEP_SPACE_FREED[1]})${NC}"
else
    echo -e "${YELLOW}⏺️ No change in space${NC}"
fi

# -------------------------
# STEP 2: Truncate LSWS logs
# -------------------------
print_step_header "2" "LSWS Logs Truncation"
STEP2_BEFORE=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $STEP2_BEFORE)${NC}"

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
if [ $lsws_logs_size -gt 0 ]; then
    find /usr/local/lsws/logs -type f -name '*.log.*' -exec truncate -s 0 {} \; 2>/dev/null
    echo -e "${GREEN}✓ Logs truncated${NC}"
else
    echo -e "${YELLOW}⚠️ No LSWS logs found to truncate${NC}"
fi

# Wait a moment for disk operations to complete
sleep 2
STEP2_AFTER=$(get_available_space)
STEP_SPACE_FREED[2]=$(measure_step_space 2 $STEP2_BEFORE $STEP2_AFTER)

echo -e "${CYAN}Space after: $(human_readable $STEP2_AFTER)${NC}"
if [ ${STEP_SPACE_FREED[2]} -gt 0 ]; then
    echo -e "${GREEN}✅ Freed: $(human_readable ${STEP_SPACE_FREED[2]})${NC}"
elif [ ${STEP_SPACE_FREED[2]} -lt 0 ]; then
    echo -e "${RED}⚠️ Lost: $(human_readable ${STEP_SPACE_FREED[2]})${NC}"
else
    echo -e "${YELLOW}⏺️ No change in space${NC}"
fi

# -------------------------
# STEP 3: Clean LSWS cache
# -------------------------
print_step_header "3" "LSWS Cache Cleanup"
STEP3_BEFORE=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $STEP3_BEFORE)${NC}"

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
if [ $cache_size -gt 0 ]; then
    rm -rf /usr/local/lsws/cachedata/* 2>/dev/null
    echo -e "${GREEN}✓ Cache cleaned${NC}"
else
    echo -e "${YELLOW}⚠️ No cache found to clean${NC}"
fi

# Wait a moment for disk operations to complete
sleep 2
STEP3_AFTER=$(get_available_space)
STEP_SPACE_FREED[3]=$(measure_step_space 3 $STEP3_BEFORE $STEP3_AFTER)

echo -e "${CYAN}Space after: $(human_readable $STEP3_AFTER)${NC}"
if [ ${STEP_SPACE_FREED[3]} -gt 0 ]; then
    echo -e "${GREEN}✅ Freed: $(human_readable ${STEP_SPACE_FREED[3]})${NC}"
elif [ ${STEP_SPACE_FREED[3]} -lt 0 ]; then
    echo -e "${RED}⚠️ Lost: $(human_readable ${STEP_SPACE_FREED[3]})${NC}"
else
    echo -e "${YELLOW}⏺️ No change in space${NC}"
fi

# -------------------------
# STEP 4: Find and truncate large log files in /var/log
# -------------------------
print_step_header "4" "Large Log Files Truncation"
STEP4_BEFORE=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $STEP4_BEFORE)${NC}"

large_logs=$(find /var/log -type f -size +20M 2>/dev/null)
file_count=$(echo "$large_logs" | wc -l)

if [ $file_count -eq 0 ] || [ -z "$large_logs" ]; then
  echo -e "${YELLOW}⚠️ No log files larger than 20MB found${NC}"
else
  echo -e "${CYAN}Found ${YELLOW}$file_count${CYAN} large log file(s):${NC}"
  
  # Calculate total size of large logs
  total_large_logs_size=0
  file_counter=1
  while IFS= read -r logfile; do
    if [ -f "$logfile" ]; then
      size=$(du -k "$logfile" 2>/dev/null | awk '{print $1}')
      if [ -n "$size" ]; then
        total_large_logs_size=$((total_large_logs_size + size))
        filename=$(basename "$logfile")
        echo -e "  ${RED}${file_counter}.${NC} ${filename} (${YELLOW}$(human_readable $size)${NC})"
        file_counter=$((file_counter + 1))
      fi
    fi
  done <<< "$large_logs"
  
  if [ $total_large_logs_size -gt 0 ]; then
    echo -e "${CYAN}Total size: $(human_readable $total_large_logs_size)${NC}"
    
    # Truncate the logs
    find /var/log -type f -size +20M -exec truncate -s 0 {} \; 2>/dev/null
    echo -e "${GREEN}✓ Large logs truncated${NC}"
  fi
fi

# Wait a moment for disk operations to complete
sleep 2
STEP4_AFTER=$(get_available_space)
STEP_SPACE_FREED[4]=$(measure_step_space 4 $STEP4_BEFORE $STEP4_AFTER)

echo -e "${CYAN}Space after: $(human_readable $STEP4_AFTER)${NC}"
if [ ${STEP_SPACE_FREED[4]} -gt 0 ]; then
    echo -e "${GREEN}✅ Freed: $(human_readable ${STEP_SPACE_FREED[4]})${NC}"
elif [ ${STEP_SPACE_FREED[4]} -lt 0 ]; then
    echo -e "${RED}⚠️ Lost: $(human_readable ${STEP_SPACE_FREED[4]})${NC}"
else
    echo -e "${YELLOW}⏺️ No change in space${NC}"
fi

# -------------------------
# STEP 5: Clean journalctl logs
# -------------------------
print_step_header "5" "Journal Logs Cleanup"
STEP5_BEFORE=$(get_available_space)
echo -e "${CYAN}Space before: $(human_readable $STEP5_BEFORE)${NC}"

# Get journal size before cleanup
journal_size_before=0
journal_output=$(journalctl --disk-usage 2>/dev/null)
if [ -n "$journal_output" ]; then
    journal_size_before=$(echo "$journal_output" | awk '{print $1}' | sed 's/[^0-9]*//g')
    if [ -z "$journal_size_before" ]; then
        journal_size_before=0
    fi
fi

if [ $journal_size_before -gt 0 ]; then
    echo -e "${CYAN}Journal size: $(human_readable $journal_size_before)${NC}"
    
    # Clean journal
    echo -e "${CYAN}Cleaning journal logs...${NC}"
    journalctl --rotate 2>/dev/null
    journalctl --vacuum-time=1s 2>/dev/null
    echo -e "${GREEN}✓ Journal cleaned${NC}"
else
    echo -e "${YELLOW}⚠️ No journal logs found to clean${NC}"
fi

# Wait a moment for disk operations to complete
sleep 2
STEP5_AFTER=$(get_available_space)
STEP_SPACE_FREED[5]=$(measure_step_space 5 $STEP5_BEFORE $STEP5_AFTER)

echo -e "${CYAN}Space after: $(human_readable $STEP5_AFTER)${NC}"
if [ ${STEP_SPACE_FREED[5]} -gt 0 ]; then
    echo -e "${GREEN}✅ Freed: $(human_readable ${STEP_SPACE_FREED[5]})${NC}"
elif [ ${STEP_SPACE_FREED[5]} -lt 0 ]; then
    echo -e "${RED}⚠️ Lost: $(human_readable ${STEP_SPACE_FREED[5]})${NC}"
else
    echo -e "${YELLOW}⏺️ No change in space${NC}"
fi

# -------------------------
# FINAL SUMMARY
# -------------------------
print_separator
echo -e "${BLUE}${BOLD}📋 FINAL MAINTENANCE REPORT${NC}"
print_separator

# Get final disk space
FINAL_SPACE=$(get_available_space)

# Calculate total space freed correctly
# Space freed = Final space - Initial space (positive means more space available)
TOTAL_SPACE_FREED=$((FINAL_SPACE - INITIAL_SPACE))

# Print summary tables
print_summary_table
print_steps_table
print_improvement

# Print final message
echo -e "\n${GREEN}${BOLD}🎯 MAINTENANCE RESULTS:${NC}"

# Use absolute value for comparison
TOTAL_ABSOLUTE=$TOTAL_SPACE_FREED
if [ $TOTAL_ABSOLUTE -lt 0 ]; then
    TOTAL_ABSOLUTE=$((TOTAL_ABSOLUTE * -1))
fi

if [ $TOTAL_SPACE_FREED -gt 1048576 ]; then  # More than 1GB
    echo -e "${GREEN}✅ Excellent! Freed over 1 GB of disk space${NC}"
elif [ $TOTAL_SPACE_FREED -gt 512000 ]; then  # More than 500MB
    echo -e "${GREEN}✅ Good job! Freed significant disk space${NC}"
elif [ $TOTAL_SPACE_FREED -gt 10240 ]; then  # More than 10MB
    echo -e "${GREEN}✅ Some space was freed${NC}"
elif [ $TOTAL_SPACE_FREED -gt 0 ]; then  # Positive but small
    echo -e "${GREEN}✅ Small amount of space freed${NC}"
elif [ $TOTAL_SPACE_FREED -lt 0 ]; then  # Negative (space decreased)
    echo -e "${RED}⚠️ Warning: Disk space decreased by $(human_readable $TOTAL_ABSOLUTE)${NC}"
    echo -e "${YELLOW}This could be due to new files being created during cleanup${NC}"
else  # Zero
    echo -e "${YELLOW}⏺️ No change in disk space${NC}"
fi

print_footer

# Cleanup - no temporary files to clean
echo -e "\n${YELLOW}🧹 All cleanup operations completed${NC}"
echo -e "${GREEN}✓ No temporary files were created${NC}"
echo -e "${GREEN}✓ Script execution finished${NC}"
