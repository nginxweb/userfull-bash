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

# ---------------- SERVER INFO ----------------
HOST=$(hostname)
CURRENT_DATE=$(date "+%Y-%m-%d %H:%M:%S")
CURRENT_DATE_SHORT=$(date "+%Y/%m/%d")

echo -e "${CYAN}===== SYSTEM ANALYSIS =====${NC}"
echo -e "${CYAN}Server: ${HOST}${NC}"
echo -e "${CYAN}Date  : ${CURRENT_DATE}${NC}"

# ---------------- CPU ----------------
CPU_CORES=$(nproc)
LOAD_1=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)

LOAD_PERCENT=$(echo "scale=2; ($LOAD_1 / $CPU_CORES) * 100" | bc)
LOAD_PERCENT_INT=$(echo "$LOAD_PERCENT" | cut -d. -f1)

echo -e "\n${BLUE}----- CPU ANALYSIS -----${NC}"
echo -e "Current CPU Cores : ${CYAN}$CPU_CORES${NC}"
echo -e "Current Load      : ${CYAN}$LOAD_1${NC}"
echo -e "Load Percentage   : ${CYAN}${LOAD_PERCENT}% of cores${NC}"

if (( LOAD_PERCENT_INT >= 90 )); then
    REC_CPU=$(echo "$CPU_CORES * 1.5" | bc | awk '{print int($1)+1}')
    echo -e "Status: ${RED}Load ${LOAD_PERCENT}% >= 90% of cores${NC}"
    echo -e "Action: ${YELLOW}Add 50% more cores${NC}"
elif (( LOAD_PERCENT_INT >= 70 )); then
    REC_CPU=$(echo "$CPU_CORES * 1.5" | bc | awk '{print int($1)+1}')
    echo -e "Status: ${YELLOW}Load ${LOAD_PERCENT}% >= 70% of cores${NC}"
    echo -e "Action: ${YELLOW}Add 50% more cores${NC}"
else
    REC_CPU=$CPU_CORES
    echo -e "Status: ${GREEN}Load ${LOAD_PERCENT}% < 70% of cores${NC}"
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

if (( RAM_USAGE_PCT >= 70 )); then
    REC_RAM=$(echo "$TOTAL_RAM_GB * 1.5" | bc | awk '{print int($1)+1}')
    echo -e "Status: ${YELLOW}RAM usage ${RAM_USAGE_PCT}% >= 70%${NC}"
    echo -e "Action: ${YELLOW}Add 50% more RAM${NC}"
else
    REC_RAM=$(echo "$TOTAL_RAM_GB" | bc | awk '{print int($1)}')
    echo -e "Status: ${GREEN}RAM usage ${RAM_USAGE_PCT}% < 70%${NC}"
    echo -e "Action: ${GREEN}Keep same RAM${NC}"
fi

echo -e "Recommended RAM   : ${CYAN}$REC_RAM GB${NC}"

# ---------------- DISK ----------------
# Get total of ALL physical disks
TOTAL_DISK_BYTES=0
DISK_LIST=$(lsblk -d -b -o NAME,SIZE,TYPE 2>/dev/null | grep -E 'disk$' | awk '{print $2}')

if [ -z "$DISK_LIST" ]; then
    DISK_LIST=$(lsblk -b -o NAME,SIZE 2>/dev/null | grep -v "^NAME" | awk '{print $2}')
fi

for size in $DISK_LIST; do
    if [[ $size =~ ^[0-9]+$ ]]; then
        TOTAL_DISK_BYTES=$((TOTAL_DISK_BYTES + size))
    fi
done

if [ "$TOTAL_DISK_BYTES" -eq 0 ]; then
    TOTAL_DISK_GB=$(df -BG --total 2>/dev/null | awk '/total/ {print $2}' | sed 's/G//')
    if [ -n "$TOTAL_DISK_GB" ]; then
        TOTAL_DISK_BYTES=$((TOTAL_DISK_GB * 1024 * 1024 * 1024))
    fi
fi

TOTAL_DISK_TB_RAW=$(echo "scale=2; $TOTAL_DISK_BYTES / 1024 / 1024 / 1024 / 1024" | bc)
if [ -z "$TOTAL_DISK_TB_RAW" ] || [ "$TOTAL_DISK_TB_RAW" = "0" ]; then
    TOTAL_DISK_TB_RAW=0
fi

USED_DISK_GB=$(df -BG --total 2>/dev/null | awk '/total/ {print $3}' | sed 's/G//')
if [ -z "$USED_DISK_GB" ]; then
    USED_DISK_GB=0
fi
USED_DISK_TB=$(echo "scale=2; $USED_DISK_GB / 1024" | bc)
DISK_USAGE_PCT=$(df --total 2>/dev/null | awk '/total/ {print $5}' | sed 's/%//')
if [ -z "$DISK_USAGE_PCT" ]; then
    DISK_USAGE_PCT=0
fi

echo -e "\n${BLUE}----- DISK ANALYSIS -----${NC}"
echo -e "${CYAN}Storage Devices Found:${NC}"
if lsblk -d -o NAME,SIZE,MODEL 2>/dev/null | grep -E '^sd|^nvme|^vd|^hd' > /dev/null; then
    lsblk -d -o NAME,SIZE,MODEL 2>/dev/null | grep -E '^sd|^nvme|^vd|^hd' | while read line; do
        echo -e "  ${GREEN}$line${NC}"
    done
else
    lsblk -o NAME,SIZE,TYPE 2>/dev/null | head -10 | while read line; do
        echo -e "  ${GREEN}$line${NC}"
    done
fi

echo -e "\nCurrent Total Storage: ${CYAN}${TOTAL_DISK_TB_RAW} TB${NC}"
echo -e "Current Used Space   : ${CYAN}${USED_DISK_TB} TB (${DISK_USAGE_PCT}%)${NC}"

# DISK Logic - Calculate recommended disk
if (( DISK_USAGE_PCT >= 70 )); then
    REC_DISK_TB=$(echo "$TOTAL_DISK_TB_RAW * 1.5" | bc)
    echo -e "Status: ${YELLOW}Disk usage ${DISK_USAGE_PCT}% >= 70%${NC}"
    echo -e "Action: ${YELLOW}Add 50% more disk space${NC}"
else
    REC_DISK_TB=$TOTAL_DISK_TB_RAW
    echo -e "Status: ${GREEN}Disk usage ${DISK_USAGE_PCT}% < 70%${NC}"
    echo -e "Action: ${GREEN}Keep same disk space${NC}"
fi

# FIXED: Ensure REC_DISK_TB is never less than TOTAL_DISK_TB_RAW
if (( $(echo "$REC_DISK_TB < $TOTAL_DISK_TB_RAW" | bc -l) )); then
    REC_DISK_TB=$TOTAL_DISK_TB_RAW
fi

# FIXED: Round up to next whole number (not nearest)
# For 1.26 -> 2, for 2.24 -> 3, for 3.8 -> 4, for 4.1 -> 5
REC_DISK_TB_CEIL=$(echo "$REC_DISK_TB" | awk '{print int($1)+1}')
# But if it's already a whole number, don't add 1
if (( $(echo "$REC_DISK_TB == $REC_DISK_TB_CEIL - 1" | bc -l) )); then
    REC_DISK_TB_CEIL=$((REC_DISK_TB_CEIL - 1))
fi
REC_DISK_TB=$REC_DISK_TB_CEIL

# Final safety: ensure at least 1 TB
if (( REC_DISK_TB < 1 )); then
    REC_DISK_TB=1
fi

echo -e "Recommended Disk     : ${CYAN}${REC_DISK_TB} TB${NC}"

# ---------------- REALISTIC MARKET VALUES ----------------
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

DISK_OPTIONS=(1 2 3 4 6 8 10 12 16 20 24 32 40 48 64 80 100)
REAL_REC_DISK=$REC_DISK_TB
for d in "${DISK_OPTIONS[@]}"; do 
    if (( d >= REC_DISK_TB )); then 
        REAL_REC_DISK=$d
        break
    fi
done

# ---------------- FINAL OUTPUT ----------------
echo -e "\n${MAGENTA}===== FINAL RECOMMENDATION =====${NC}"
echo -e "${CYAN}Server: ${HOST} | Date: ${CURRENT_DATE_SHORT}${NC}"
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
printf "%-15s %-20s %-20s\n" "Disk" "${TOTAL_DISK_TB_RAW} TB" "${REAL_REC_DISK} TB"

echo ""
