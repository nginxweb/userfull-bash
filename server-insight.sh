#!/bin/bash
# =====================================================
# Script Name  : server-insight.sh
# Author       : Eric Smith
# Company      : ultahost.com
# Description  : Smart hardware recommendations based on actual usage
# =====================================================

# ---------------- COLORS ----------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

echo -e "${CYAN}===== SYSTEM ANALYSIS =====${NC}"

HOST=$(hostname)

# ---------------- CPU ----------------
CPU_CORES=$(nproc)
LOAD_1=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)

# Convert load to integer for comparison
LOAD_INT=$(printf "%.0f" "$LOAD_1")

echo -e "\n${BLUE}----- CPU ANALYSIS -----${NC}"
echo -e "Current CPU Cores : ${CYAN}$CPU_CORES${NC}"
echo -e "Current Load      : ${CYAN}$LOAD_1${NC}"

# CPU Logic: Compare load vs cores
if (( LOAD_INT >= CPU_CORES )); then
    # Load is equal to or higher than cores -> add 50%
    REC_CPU=$(echo "$CPU_CORES * 1.5" | bc | awk '{print int($1)+1}')
    echo -e "Status: ${YELLOW}Load >= Cores (${LOAD_INT} >= ${CPU_CORES})${NC}"
    echo -e "Action: ${YELLOW}Add 50% more cores${NC}"
elif (( LOAD_INT <= CPU_CORES / 2 )); then
    # Load is 50% or less of cores -> keep same
    REC_CPU=$CPU_CORES
    echo -e "Status: ${GREEN}Load <= 50% of Cores (${LOAD_INT} <= $((CPU_CORES / 2)))${NC}"
    echo -e "Action: ${GREEN}Keep same cores${NC}"
else
    # Load is between 50% and 100% -> keep same
    REC_CPU=$CPU_CORES
    echo -e "Status: ${GREEN}Load within normal range${NC}"
    echo -e "Action: ${GREEN}Keep same cores${NC}"
fi

echo -e "Recommended CPU   : ${CYAN}$REC_CPU cores${NC}"

# ---------------- RAM ----------------
read TOTAL_RAM_MB USED_RAM_MB <<< $(free -m | awk '/Mem:/ {print $2, $2-$7}')
TOTAL_RAM_GB=$(echo "scale=2; $TOTAL_RAM_MB / 1024" | bc)
USED_RAM_GB=$(echo "scale=2; $USED_RAM_MB / 1024" | bc)
RAM_USAGE_PCT=$(echo "scale=0; ($USED_RAM_MB * 100) / $TOTAL_RAM_MB" | bc)

echo -e "\n${BLUE}----- RAM ANALYSIS -----${NC}"
echo -e "Current Total RAM : ${CYAN}${TOTAL_RAM_GB} GB${NC}"
echo -e "Current Used RAM  : ${CYAN}${USED_RAM_GB} GB (${RAM_USAGE_PCT}%)${NC}"

# RAM Logic: Check if used RAM is 70% or more of total
if (( RAM_USAGE_PCT >= 70 )); then
    # Used RAM is 70% or more -> add 50%
    REC_RAM=$(echo "$TOTAL_RAM_GB * 1.5" | bc | awk '{print int($1)+1}')
    echo -e "Status: ${YELLOW}RAM usage ${RAM_USAGE_PCT}% >= 70%${NC}"
    echo -e "Action: ${YELLOW}Add 50% more RAM${NC}"
else
    # Used RAM is less than 70% -> keep same
    REC_RAM=$(echo "$TOTAL_RAM_GB" | bc | awk '{print int($1)}')
    echo -e "Status: ${GREEN}RAM usage ${RAM_USAGE_PCT}% < 70%${NC}"
    echo -e "Action: ${GREEN}Keep same RAM${NC}"
fi

echo -e "Recommended RAM   : ${CYAN}$REC_RAM GB${NC}"

# ---------------- DISK ----------------
TOTAL_DISK_GB=$(df -BG --total | awk '/total/ {print $2}' | sed 's/G//')
USED_DISK_GB=$(df -BG --total | awk '/total/ {print $3}' | sed 's/G//')
TOTAL_DISK_TB=$(echo "scale=2; $TOTAL_DISK_GB / 1024" | bc)
USED_DISK_TB=$(echo "scale=2; $USED_DISK_GB / 1024" | bc)
DISK_USAGE_PCT=$(df --total | awk '/total/ {print $5}' | sed 's/%//')

echo -e "\n${BLUE}----- DISK ANALYSIS -----${NC}"
echo -e "Current Total Disk: ${CYAN}${TOTAL_DISK_TB} TB${NC}"
echo -e "Current Used Disk : ${CYAN}${USED_DISK_TB} TB (${DISK_USAGE_PCT}%)${NC}"

# DISK Logic: Check if used disk is 70% or more of total
if (( DISK_USAGE_PCT >= 70 )); then
    # Used disk is 70% or more -> add 50% more space
    REC_DISK_GB=$(echo "$TOTAL_DISK_GB * 1.5" | bc)
    REC_DISK_TB=$(echo "scale=2; $REC_DISK_GB / 1024" | bc)
    echo -e "Status: ${YELLOW}Disk usage ${DISK_USAGE_PCT}% >= 70%${NC}"
    echo -e "Action: ${YELLOW}Add 50% more disk space${NC}"
else
    # Used disk is less than 70% -> keep same
    REC_DISK_TB=$TOTAL_DISK_TB
    echo -e "Status: ${GREEN}Disk usage ${DISK_USAGE_PCT}% < 70%${NC}"
    echo -e "Action: ${GREEN}Keep same disk space${NC}"
fi

echo -e "Recommended Disk  : ${CYAN}${REC_DISK_TB} TB${NC}"

# ---------------- REALISTIC MARKET VALUES ----------------
# Round up to realistic market options
CPU_OPTIONS=(4 6 8 12 16 20 24 32 40 48 64 80 96 128)
REAL_REC_CPU=$REC_CPU
for opt in "${CPU_OPTIONS[@]}"; do 
    if (( opt >= REC_CPU )); then 
        REAL_REC_CPU=$opt
        break
    fi
done

RAM_OPTIONS=(8 16 24 32 48 64 96 128 192 256 384 512 768 1024)
REAL_REC_RAM=$REC_RAM
for ram in "${RAM_OPTIONS[@]}"; do 
    if (( ram >= REC_RAM )); then 
        REAL_REC_RAM=$ram
        break
    fi
done

DISK_OPTIONS=(0.5 1 2 3 4 6 8 10 12 16 20 24 32 40 48 64 80 100)
REAL_REC_DISK=$REC_DISK_TB
for d in "${DISK_OPTIONS[@]}"; do 
    if (( $(echo "$d >= $REC_DISK_TB" | bc -l) )); then 
        REAL_REC_DISK=$d
        break
    fi
done

# ---------------- FINAL OUTPUT ----------------
echo -e "\n${MAGENTA}===== FINAL RECOMMENDATION =====${NC}"
echo -e "${CYAN}Recommended Hardware:${NC}"
echo -e "  CPU : ${REAL_REC_CPU} cores"
echo -e "  RAM : ${REAL_REC_RAM} GB"
echo -e "  Disk: ${REAL_REC_DISK} TB"

# ---------------- SUMMARY TABLE ----------------
echo -e "\n${BLUE}----- SUMMARY -----${NC}"
printf "%-15s %-20s %-20s\n" "Component" "Current" "Recommended"
printf "%-15s %-20s %-20s\n" "----------" "-------------------" "-------------------"
printf "%-15s %-20s %-20s\n" "CPU" "${CPU_CORES} cores" "${REAL_REC_CPU} cores"
printf "%-15s %-20s %-20s\n" "RAM" "${TOTAL_RAM_GB} GB" "${REAL_REC_RAM} GB"
printf "%-15s %-20s %-20s\n" "Disk" "${TOTAL_DISK_TB} TB" "${REAL_REC_DISK} TB"

echo ""
