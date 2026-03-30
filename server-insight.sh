#!/bin/bash
# =====================================================
# Script Name  : server-insight.sh
# Author       : Eric Smith
# Company      : ultahost.com
# Description  : Gathers system metrics and provides
#                workload classification & recommendations
# =====================================================

# ---------------- COLORS ----------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m' # No Color

echo -e "${CYAN}===== ADVANCED SYSTEM ANALYSIS By Eric Smith =====${NC}"

HOST=$(hostname)

# ---------------- CPU ----------------
CPU_CORES=$(nproc)
LOAD_1=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)

CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d. -f1)
CPU_USAGE=$((100 - CPU_IDLE))

# ---------------- RAM ----------------
read TOTAL_RAM_MB USED_RAM_MB <<< $(free -m | awk '/Mem:/ {print $2, $2-$7}')
AVAILABLE_RAM_MB=$(free -m | awk '/Mem:/ {print $7}')

TOTAL_RAM_GB=$(echo "scale=2; $TOTAL_RAM_MB / 1024" | bc)
USED_RAM_GB=$(echo "scale=2; $USED_RAM_MB / 1024" | bc)
AVAILABLE_RAM_GB=$(echo "scale=2; $AVAILABLE_RAM_MB / 1024" | bc)

SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')

# ---------------- DISK ----------------
TOTAL_DISK_GB=$(df -BG --total | awk '/total/ {print $2}' | sed 's/G//')
USED_DISK_GB=$(df -BG --total | awk '/total/ {print $3}' | sed 's/G//')

TOTAL_DISK_TB=$(echo "scale=2; $TOTAL_DISK_GB / 1024" | bc)
USED_DISK_TB=$(echo "scale=2; $USED_DISK_GB / 1024" | bc)

DISK_USAGE_PCT=$(df --total | awk '/total/ {print $5}' | sed 's/%//')

# ---------------- IO ----------------
IO_UTIL=$(iostat -x 1 2 | awk '/Device/ {getline} {print $NF}' | sort -nr | head -1)
IO_UTIL=${IO_UTIL:-0}

# ---------------- CLASSIFICATION ----------------
TYPE="Balanced"

if (( CPU_USAGE > 70 )); then
  TYPE="CPU Intensive"
fi

if (( USED_RAM_MB > (TOTAL_RAM_MB * 75 / 100) )); then
  TYPE="Memory Intensive"
fi

if (( DISK_USAGE_PCT > 80 )); then
  TYPE="Storage Intensive"
fi

if (( $(echo "$IO_UTIL > 70" | bc -l) )); then
  TYPE="IO Intensive"
fi

# ---------------- SAFETY FACTOR ----------------
FACTOR_REC=1.5
FACTOR_IDEAL=2

if (( $(echo "$LOAD_1 > $CPU_CORES" | bc -l) )); then
  FACTOR_REC=2
  FACTOR_IDEAL=3
fi

# ---------------- RECOMMENDATIONS ----------------
REC_CPU=$(echo "$LOAD_1 * $FACTOR_REC" | bc | awk '{print ($1 < 1 ? 1 : int($1)+1)}')
IDEAL_CPU=$(echo "$LOAD_1 * $FACTOR_IDEAL" | bc | awk '{print ($1 < 2 ? 2 : int($1)+1)}')

REC_RAM_MB=$(echo "$USED_RAM_MB * $FACTOR_REC" | bc)
IDEAL_RAM_MB=$(echo "$USED_RAM_MB * $FACTOR_IDEAL" | bc)

# Swap-aware RAM adjustment
if (( SWAP_USED > 0 )); then
  REC_RAM_MB=$(echo "$REC_RAM_MB * 1.25" | bc)
  IDEAL_RAM_MB=$(echo "$IDEAL_RAM_MB * 1.25" | bc)
fi

REC_RAM_GB=$(echo "scale=2; $REC_RAM_MB / 1024" | bc)
IDEAL_RAM_GB=$(echo "scale=2; $IDEAL_RAM_MB / 1024" | bc)

REC_DISK_GB=$(echo "$USED_DISK_GB * $FACTOR_REC" | bc)
IDEAL_DISK_GB=$(echo "$USED_DISK_GB * $FACTOR_IDEAL" | bc)

REC_DISK_TB=$(echo "scale=2; $REC_DISK_GB / 1024" | bc)
IDEAL_DISK_TB=$(echo "scale=2; $IDEAL_DISK_GB / 1024" | bc)

# ---------------- STATUS ----------------
RAM_STATUS=$GREEN
CPU_STATUS=$GREEN
DISK_STATUS=$GREEN

RAM_TEXT="OK"
CPU_TEXT="OK"
DISK_TEXT="OK"

if (( USED_RAM_MB > (TOTAL_RAM_MB * 80 / 100) )); then
  RAM_STATUS=$YELLOW
  RAM_TEXT="HIGH"
fi

if (( CPU_USAGE > 80 )); then
  CPU_STATUS=$YELLOW
  CPU_TEXT="HIGH"
fi

if (( DISK_USAGE_PCT > 85 )); then
  DISK_STATUS=$RED
  DISK_TEXT="CRITICAL"
fi

# ---------------- CPANEL ACCOUNTS ----------------
CPANEL_INSTALLED=0
CPANEL_ACCOUNTS=0
RESELLER_ACCOUNTS=0

if [ -x "/usr/local/cpanel/cpanel" ]; then
  CPANEL_INSTALLED=1
  # تعداد اکانت‌های سی پنل
  CPANEL_ACCOUNTS=$(whmapi1 listaccts | grep -c "user:")
  # تعداد اکانت‌های ریسلر
  RESELLER_ACCOUNTS=$(whmapi1 listaccts | grep -B 10 "Reseller: 1" | grep "user:" | wc -l)
fi

# ---------------- OUTPUT ----------------
echo -e "\n${BLUE}----- CURRENT USAGE -----${NC}"
echo -e "Host            : ${CYAN}$HOST${NC}"
echo -e "CPU             : ${CPU_CORES} cores | ${CPU_STATUS}${CPU_TEXT}${NC} | Load: $LOAD_1"
echo -e "RAM             : ${USED_RAM_GB} / ${TOTAL_RAM_GB} GB | Available: ${AVAILABLE_RAM_GB} GB | Status: ${RAM_STATUS}${RAM_TEXT}${NC}"
echo -e "Swap Used       : ${SWAP_USED} MB"
echo -e "Disk            : ${USED_DISK_TB} / ${TOTAL_DISK_TB} TB (${DISK_USAGE_PCT}%) | Status: ${DISK_STATUS}${DISK_TEXT}${NC}"
echo -e "IO Utilization  : ${IO_UTIL}%"

echo -e "\n${MAGENTA}----- CLASSIFICATION -----${NC}"
echo -e "Workload Type   : ${YELLOW}$TYPE${NC}"

echo -e "\n${MAGENTA}----- RECOMMENDATION -----${NC}"
echo -e "${CYAN}Recommended:${NC}"
echo -e "CPU Cores : $REC_CPU"
echo -e "RAM       : ${REC_RAM_GB} GB"
echo -e "Disk      : ${REC_DISK_TB} TB"

echo -e "\n${CYAN}Ideal:${NC}"
echo -e "CPU Cores : $IDEAL_CPU"
echo -e "RAM       : ${IDEAL_RAM_GB} GB"
echo -e "Disk      : ${IDEAL_DISK_TB} TB"

echo -e "\n${MAGENTA}===== EXECUTIVE SUMMARY =====${NC}"
echo -e "Server Type     : ${YELLOW}$TYPE${NC}"
echo -e "CPU Status      : ${CPU_STATUS}$CPU_TEXT${NC}"
echo -e "RAM Status      : ${RAM_STATUS}$RAM_TEXT${NC}"
echo -e "Disk Status     : ${DISK_STATUS}$DISK_TEXT${NC}"

if (( SWAP_USED > 0 )); then
  echo -e "${RED}⚠ Swap in use → Memory pressure detected${NC}"
fi

if (( DISK_USAGE_PCT > 85 )); then
  echo -e "${RED}⚠ Disk nearing capacity${NC}"
fi

# ---------------- CPANEL OUTPUT ----------------
if (( CPANEL_INSTALLED )); then
  echo -e "\n${MAGENTA}----- CPANEL ACCOUNTS -----${NC}"
  echo -e "Total cPanel Accounts   : ${YELLOW}$CPANEL_ACCOUNTS${NC}"
  echo -e "Reseller Accounts       : ${YELLOW}$RESELLER_ACCOUNTS${NC}"
fi

echo -e "\n${CYAN}===== JSON OUTPUT =====${NC}"
echo "{"
echo "  \"host\": \"$HOST\","
echo "  \"type\": \"$TYPE\","
echo "  \"cpu\": {\"current\": $CPU_CORES, \"recommended\": $REC_CPU, \"ideal\": $IDEAL_CPU},"
echo "  \"ram_gb\": {\"used\": $USED_RAM_GB, \"recommended\": $REC_RAM_GB, \"ideal\": $IDEAL_RAM_GB},"
echo "  \"disk_tb\": {\"used\": $USED_DISK_TB, \"recommended\": $REC_DISK_TB, \"ideal\": $IDEAL_DISK_TB}"
echo "}"
