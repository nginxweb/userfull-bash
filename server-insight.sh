#!/bin/bash
# =====================================================
# Script Name  : server-insight.sh
# Author       : Eric Smith
# Company      : ultahost.com
# Description  : Realistic hardware recommendations
# =====================================================

# ---------------- COLORS ----------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

echo -e "${CYAN}===== ADVANCED SYSTEM ANALYSIS By Eric Smith =====${NC}"

HOST=$(hostname)

# ---------------- CPU ----------------
CPU_CORES=$(nproc)
LOAD_1=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d. -f1)
CPU_USAGE=$((100 - CPU_IDLE))
CPU_MODEL=$(lscpu | awk -F: '/Model name/ {print $2}' | sed 's/^[ \t]*//')
TOTAL_CPU_FREQ=$(awk -F: '/cpu MHz/ {sum += $2} END {print sum}' /proc/cpuinfo)
TOTAL_CPU_FREQ_GHZ=$(echo "scale=2; $TOTAL_CPU_FREQ / 1000" | bc)

# Calculate CPU utilization percentage
CPU_UTIL_PCT=$(echo "scale=1; ($LOAD_1 / $CPU_CORES) * 100" | bc)

# ---------------- RAM ----------------
read TOTAL_RAM_MB USED_RAM_MB <<< $(free -m | awk '/Mem:/ {print $2, $2-$7}')
AVAILABLE_RAM_MB=$(free -m | awk '/Mem:/ {print $7}')
TOTAL_RAM_GB=$(echo "scale=2; $TOTAL_RAM_MB / 1024" | bc)
USED_RAM_GB=$(echo "scale=2; $USED_RAM_MB / 1024" | bc)
AVAILABLE_RAM_GB=$(echo "scale=2; $AVAILABLE_RAM_MB / 1024" | bc)
SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')
RAM_USAGE_PCT=$(echo "scale=0; ($USED_RAM_MB * 100) / $TOTAL_RAM_MB" | bc)

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
if (( CPU_USAGE > 70 )); then TYPE="CPU Intensive"; fi
if (( RAM_USAGE_PCT > 75 )); then TYPE="Memory Intensive"; fi
if (( DISK_USAGE_PCT > 80 )); then TYPE="Storage Intensive"; fi
if (( $(echo "$IO_UTIL > 70" | bc -l) )); then TYPE="IO Intensive"; fi

# ---------------- CPANEL ACCOUNTS ----------------
CPANEL_INSTALLED=0
CPANEL_ACCOUNTS=0
RESELLER_ACCOUNTS=0
if [ -x "/usr/local/cpanel/cpanel" ]; then
  CPANEL_INSTALLED=1
  CPANEL_ACCOUNTS=$(whmapi1 listaccts 2>/dev/null | grep -c "user:" || echo 0)
  RESELLER_ACCOUNTS=$(whmapi1 listaccts 2>/dev/null | grep -B 10 "Reseller: 1" | grep "user:" | wc -l || echo 0)
fi

# =====================================================
# ========== REALISTIC RECOMMENDATION LOGIC ==========
# =====================================================

# ---------- CPU RECOMMENDATION (Realistic) ----------
# Normalize load per core - Load of 40 on 32 cores = 1.25 per core
LOAD_PER_CORE=$(echo "scale=2; $LOAD_1 / $CPU_CORES" | bc)

# Calculate recommended cores based on actual need
if (( $(echo "$LOAD_PER_CORE > 1.5" | bc -l) )); then
    # Overloaded: add 25-50% more cores
    REC_CPU_MULT=1.5
    IDEAL_CPU_MULT=2.0
elif (( $(echo "$LOAD_PER_CORE > 1.0" | bc -l) )); then
    # High load: add 10-25% more cores
    REC_CPU_MULT=1.25
    IDEAL_CPU_MULT=1.5
elif (( $(echo "$LOAD_PER_CORE > 0.7" | bc -l) )); then
    # Moderate load: add 0-10%
    REC_CPU_MULT=1.0
    IDEAL_CPU_MULT=1.25
else
    # Low load: keep same or slightly less
    REC_CPU_MULT=0.8
    IDEAL_CPU_MULT=1.0
fi

# Never recommend less than 50% of current cores
if (( $(echo "$REC_CPU_MULT < 0.5" | bc -l) )); then REC_CPU_MULT=0.5; fi

REC_CPU_CORES=$(echo "$CPU_CORES * $REC_CPU_MULT" | bc | awk '{print int($1)+1}')
IDEAL_CPU_CORES=$(echo "$CPU_CORES * $IDEAL_CPU_MULT" | bc | awk '{print int($1)+1}')

# Cap at reasonable maximum (no more than 2x current for balanced systems)
if [[ "$TYPE" != "CPU Intensive" ]]; then
    if (( REC_CPU_CORES > CPU_CORES * 2 )); then REC_CPU_CORES=$((CPU_CORES * 2)); fi
    if (( IDEAL_CPU_CORES > CPU_CORES * 2 )); then IDEAL_CPU_CORES=$((CPU_CORES * 2)); fi
else
    # CPU intensive can go up to 3x
    if (( REC_CPU_CORES > CPU_CORES * 3 )); then REC_CPU_CORES=$((CPU_CORES * 3)); fi
    if (( IDEAL_CPU_CORES > CPU_CORES * 3 )); then IDEAL_CPU_CORES=$((CPU_CORES * 3)); fi
fi

# cPanel-based adjustment (realistic: 1 core per 30-50 accounts)
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    CPANEL_MIN_CORES=$(( (CPANEL_ACCOUNTS / 40) + 2 ))
    if (( CPANEL_MIN_CORES > REC_CPU_CORES )); then
        REC_CPU_CORES=$CPANEL_MIN_CORES
    fi
    if (( CPANEL_MIN_CORES + 4 > IDEAL_CPU_CORES )); then
        IDEAL_CPU_CORES=$((CPANEL_MIN_CORES + 4))
    fi
fi

# ---------- RAM RECOMMENDATION (Realistic) ----------
# cPanel rule of thumb: 1-2GB per account + overhead
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    CPANEL_RAM_GB=$(( (CPANEL_ACCOUNTS / 2) + 8 ))
else
    CPANEL_RAM_GB=0
fi

# Based on current usage with headroom
if (( RAM_USAGE_PCT > 80 )); then
    REC_RAM_GB=$(echo "$USED_RAM_GB * 1.5" | bc)
    IDEAL_RAM_GB=$(echo "$USED_RAM_GB * 2.0" | bc)
elif (( RAM_USAGE_PCT > 60 )); then
    REC_RAM_GB=$(echo "$USED_RAM_GB * 1.25" | bc)
    IDEAL_RAM_GB=$(echo "$USED_RAM_GB * 1.5" | bc)
else
    REC_RAM_GB=$(echo "$USED_RAM_GB * 1.1" | bc)
    IDEAL_RAM_GB=$(echo "$USED_RAM_GB * 1.25" | bc)
fi

# Take the higher of usage-based or cPanel-based recommendation
if (( $(echo "$CPANEL_RAM_GB > $REC_RAM_GB" | bc -l) )); then
    REC_RAM_GB=$CPANEL_RAM_GB
fi
if (( $(echo "$CPANEL_RAM_GB * 1.5 > $IDEAL_RAM_GB" | bc -l) )); then
    IDEAL_RAM_GB=$(echo "$CPANEL_RAM_GB * 1.5" | bc)
fi

# Ensure at least current RAM
if (( $(echo "$REC_RAM_GB < $TOTAL_RAM_GB" | bc -l) )); then
    REC_RAM_GB=$TOTAL_RAM_GB
fi
if (( $(echo "$IDEAL_RAM_GB < $TOTAL_RAM_GB" | bc -l) )); then
    IDEAL_RAM_GB=$TOTAL_RAM_GB
fi

# Cap RAM at reasonable maximum (no more than 4x current)
if (( $(echo "$IDEAL_RAM_GB > $TOTAL_RAM_GB * 4" | bc -l) )); then
    IDEAL_RAM_GB=$(echo "$TOTAL_RAM_GB * 4" | bc)
fi

# ---------- DISK RECOMMENDATION ----------
if (( DISK_USAGE_PCT > 80 )); then
    REC_DISK_TB=$(echo "$USED_DISK_TB * 2.0" | bc)
    IDEAL_DISK_TB=$(echo "$USED_DISK_TB * 3.0" | bc)
elif (( DISK_USAGE_PCT > 60 )); then
    REC_DISK_TB=$(echo "$USED_DISK_TB * 1.5" | bc)
    IDEAL_DISK_TB=$(echo "$USED_DISK_TB * 2.0" | bc)
else
    REC_DISK_TB=$(echo "$TOTAL_DISK_TB * 1.2" | bc)
    IDEAL_DISK_TB=$(echo "$TOTAL_DISK_TB * 1.5" | bc)
fi

# Ensure at least current disk
if (( $(echo "$REC_DISK_TB < $TOTAL_DISK_TB" | bc -l) )); then
    REC_DISK_TB=$TOTAL_DISK_TB
fi

# ---------------- REALISTIC HARDWARE (Market Available) ----------------
CPU_OPTIONS=(4 6 8 12 16 20 24 32 40 48 64 80 96)
for opt in "${CPU_OPTIONS[@]}"; do if (( opt >= REC_CPU_CORES )); then REAL_REC_CPU=$opt; break; fi; done
for opt in "${CPU_OPTIONS[@]}"; do if (( opt >= IDEAL_CPU_CORES )); then REAL_IDEAL_CPU=$opt; break; fi; done

RAM_OPTIONS=(16 24 32 48 64 96 128 192 256 384 512)
REC_RAM_INT=$(echo "$REC_RAM_GB" | awk '{print int($1)}')
IDEAL_RAM_INT=$(echo "$IDEAL_RAM_GB" | awk '{print int($1)}')
for ram in "${RAM_OPTIONS[@]}"; do if (( ram >= REC_RAM_INT )); then REAL_REC_RAM=$ram; break; fi; done
for ram in "${RAM_OPTIONS[@]}"; do if (( ram >= IDEAL_RAM_INT )); then REAL_IDEAL_RAM=$ram; break; fi; done

DISK_OPTIONS=(0.5 1 2 3 4 6 8 10 12 16 20 24 30 40 50)
for d in "${DISK_OPTIONS[@]}"; do if (( $(echo "$d >= $REC_DISK_TB" | bc -l) )); then REAL_REC_DISK=$d; break; fi; done
for d in "${DISK_OPTIONS[@]}"; do if (( $(echo "$d >= $IDEAL_DISK_TB" | bc -l) )); then REAL_IDEAL_DISK=$d; break; fi; done

# ---------------- STATUS ----------------
RAM_STATUS=$GREEN; CPU_STATUS=$GREEN; DISK_STATUS=$GREEN
RAM_TEXT="OK"; CPU_TEXT="OK"; DISK_TEXT="OK"
if (( RAM_USAGE_PCT > 80 )); then RAM_STATUS=$YELLOW; RAM_TEXT="HIGH"; fi
if (( CPU_USAGE > 80 )); then CPU_STATUS=$YELLOW; CPU_TEXT="HIGH"; fi
if (( DISK_USAGE_PCT > 85 )); then DISK_STATUS=$RED; DISK_TEXT="CRITICAL"; fi

# ---------------- OUTPUT ----------------
echo -e "\n${BLUE}----- CURRENT HARDWARE -----${NC}"
echo -e "Host            : ${CYAN}$HOST${NC}"
echo -e "CPU Model       : ${CYAN}$CPU_MODEL${NC}"
echo -e "CPU Cores       : ${CPU_CORES} cores"
echo -e "Load Average    : ${LOAD_1} (${CPU_UTIL_PCT}% of ${CPU_CORES} cores)"
echo -e "RAM             : ${USED_RAM_GB} / ${TOTAL_RAM_GB} GB (${RAM_USAGE_PCT}%)"
echo -e "Disk            : ${USED_DISK_TB} / ${TOTAL_DISK_TB} TB (${DISK_USAGE_PCT}%)"
echo -e "IO Utilization  : ${IO_UTIL}%"

echo -e "\n${MAGENTA}----- CLASSIFICATION -----${NC}"
echo -e "Workload Type   : ${YELLOW}$TYPE${NC}"
echo -e "Load per Core   : ${LOAD_PER_CORE}"

echo -e "\n${MAGENTA}----- REALISTIC RECOMMENDATION -----${NC}"
echo -e "${CYAN}Recommended Config (Now):${NC}"
echo -e "CPU Cores : $REAL_REC_CPU (Current: $CPU_CORES)"
echo -e "RAM       : ${REAL_REC_RAM} GB (Current: ${TOTAL_RAM_GB} GB)"
echo -e "Disk      : ${REAL_REC_DISK} TB (Current: ${TOTAL_DISK_TB} TB)"

echo -e "\n${CYAN}Ideal Config (Future Growth):${NC}"
echo -e "CPU Cores : $REAL_IDEAL_CPU"
echo -e "RAM       : ${REAL_IDEAL_RAM} GB"
echo -e "Disk      : ${REAL_IDEAL_DISK} TB"

echo -e "\n${MAGENTA}===== EXECUTIVE SUMMARY =====${NC}"
echo -e "Server Type     : ${YELLOW}$TYPE${NC}"
echo -e "Load Status     : $(if (( $(echo "$LOAD_PER_CORE < 0.7" | bc -l) )); then echo "${GREEN}LOW${NC}"; elif (( $(echo "$LOAD_PER_CORE < 1.0" | bc -l) )); then echo "${YELLOW}MODERATE${NC}"; else echo "${RED}HIGH${NC}"; fi)"
echo -e "RAM Status      : ${RAM_STATUS}$RAM_TEXT${NC}"
echo -e "Disk Status     : ${DISK_STATUS}$DISK_TEXT${NC}"

if (( SWAP_USED > 0 )); then
  echo -e "${RED}⚠ Swap in use → Memory pressure detected${NC}"
fi

if (( CPANEL_INSTALLED )); then
  echo -e "\n${MAGENTA}----- CPANEL ACCOUNTS -----${NC}"
  echo -e "Total Accounts  : ${YELLOW}$CPANEL_ACCOUNTS${NC}"
  echo -e "Resellers       : ${YELLOW}$RESELLER_ACCOUNTS${NC}"
  echo -e "${CYAN}Rule of thumb: ${CPANEL_ACCOUNTS} accounts → ~$((CPANEL_ACCOUNTS / 2))GB RAM + $((CPANEL_ACCOUNTS / 40)) CPU cores${NC}"
fi
