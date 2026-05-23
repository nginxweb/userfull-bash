#!/bin/bash
# =====================================================
# Script Name  : server-insight.sh
# Author       : Eric Smith
# Company      : ultahost.com
# Description  : Hardware recommendations for hosting servers
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
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d. -f1)
CPU_USAGE=$((100 - CPU_IDLE))
CPU_MODEL=$(lscpu | awk -F: '/Model name/ {print $2}' | sed 's/^[ \t]*//')
LOAD_PER_CORE=$(echo "scale=2; $LOAD_1 / $CPU_CORES" | bc)
CPU_UTIL_PCT=$(echo "scale=1; ($LOAD_1 / $CPU_CORES) * 100" | bc)

# ---------------- RAM ----------------
read TOTAL_RAM_MB USED_RAM_MB <<< $(free -m | awk '/Mem:/ {print $2, $2-$7}')
TOTAL_RAM_GB=$(echo "scale=2; $TOTAL_RAM_MB / 1024" | bc)
USED_RAM_GB=$(echo "scale=2; $USED_RAM_MB / 1024" | bc)
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
if (( DISK_USAGE_PCT > 70 )); then TYPE="Storage Intensive"; fi
if (( $(echo "$IO_UTIL > 70" | bc -l) )); then TYPE="IO Intensive"; fi

# ---------------- CPANEL ACCOUNTS ----------------
CPANEL_INSTALLED=0
CPANEL_ACCOUNTS=0
if [ -x "/usr/local/cpanel/cpanel" ]; then
  CPANEL_INSTALLED=1
  CPANEL_ACCOUNTS=$(whmapi1 listaccts 2>/dev/null | grep -c "user:" || echo 0)
fi

# =====================================================
# ========== RECOMMENDATION ENGINE ==========
# =====================================================

# ---------- CPU ----------
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    MIN_CPU=$(( (CPANEL_ACCOUNTS / 40) + 2 ))
else
    MIN_CPU=2
fi

if (( $(echo "$LOAD_PER_CORE > 1.0" | bc -l) )); then
    REC_CPU=$(echo "$CPU_CORES * 1.5" | bc | awk '{print int($1)+1}')
    IDEAL_CPU=$(echo "$CPU_CORES * 2" | bc | awk '{print int($1)+1}')
elif (( $(echo "$LOAD_PER_CORE > 0.7" | bc -l) )); then
    REC_CPU=$(echo "$CPU_CORES * 1.2" | bc | awk '{print int($1)+1}')
    IDEAL_CPU=$(echo "$CPU_CORES * 1.5" | bc | awk '{print int($1)+1}')
else
    REC_CPU=$CPU_CORES
    IDEAL_CPU=$(echo "$CPU_CORES * 1.25" | bc | awk '{print int($1)+1}')
fi

if (( REC_CPU < MIN_CPU )); then REC_CPU=$MIN_CPU; fi
if (( IDEAL_CPU < MIN_CPU + 2 )); then IDEAL_CPU=$((MIN_CPU + 2)); fi

# ---------- RAM ----------
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    MIN_RAM=$(( (CPANEL_ACCOUNTS / 1) + 8 ))
    IDEAL_RAM_BASE=$(( (CPANEL_ACCOUNTS * 2) + 8 ))
else
    MIN_RAM=4
    IDEAL_RAM_BASE=8
fi

if (( RAM_USAGE_PCT > 75 )); then
    REC_RAM=$(echo "$USED_RAM_GB * 1.5" | bc | awk '{print int($1)+1}')
    IDEAL_RAM=$(echo "$USED_RAM_GB * 2" | bc | awk '{print int($1)+1}')
elif (( RAM_USAGE_PCT > 50 )); then
    REC_RAM=$(echo "$USED_RAM_GB * 1.25" | bc | awk '{print int($1)+1}')
    IDEAL_RAM=$(echo "$USED_RAM_GB * 1.75" | bc | awk '{print int($1)+1}')
else
    REC_RAM=$(echo "$TOTAL_RAM_GB * 1.2" | bc | awk '{print int($1)+1}')
    IDEAL_RAM=$(echo "$TOTAL_RAM_GB * 1.5" | bc | awk '{print int($1)+1}')
fi

if (( REC_RAM < MIN_RAM )); then REC_RAM=$MIN_RAM; fi
if (( IDEAL_RAM < IDEAL_RAM_BASE )); then IDEAL_RAM=$IDEAL_RAM_BASE; fi

# ---------- DISK (CRITICAL FOR HOSTING) ----------
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    MIN_DISK_GB=$((CPANEL_ACCOUNTS * 15))
    IDEAL_DISK_GB=$((CPANEL_ACCOUNTS * 30))
else
    MIN_DISK_GB=100
    IDEAL_DISK_GB=200
fi

if (( DISK_USAGE_PCT > 70 )); then
    REC_DISK_GB=$(echo "$USED_DISK_GB * 2" | bc)
    IDEAL_DISK_GB=$(echo "$USED_DISK_GB * 3" | bc | awk '{print int($1)+100}')
elif (( DISK_USAGE_PCT > 50 )); then
    REC_DISK_GB=$(echo "$USED_DISK_GB * 1.5" | bc)
    IDEAL_DISK_GB=$(echo "$USED_DISK_GB * 2.5" | bc | awk '{print int($1)+50}')
else
    REC_DISK_GB=$(echo "$TOTAL_DISK_GB * 1.3" | bc)
    IDEAL_DISK_GB=$(echo "$TOTAL_DISK_GB * 2" | bc)
fi

if (( $(echo "$REC_DISK_GB < $MIN_DISK_GB" | bc -l) )); then
    REC_DISK_GB=$MIN_DISK_GB
fi
if (( $(echo "$IDEAL_DISK_GB < $IDEAL_DISK_GB" | bc -l) )); then
    IDEAL_DISK_GB=$IDEAL_DISK_GB
fi

REC_DISK_TB=$(echo "scale=1; $REC_DISK_GB / 1024" | bc)
IDEAL_DISK_TB=$(echo "scale=1; $IDEAL_DISK_GB / 1024" | bc)

# ---------------- REALISTIC MARKET VALUES ----------------
CPU_OPTIONS=(4 6 8 12 16 20 24 32 40 48 64)
for opt in "${CPU_OPTIONS[@]}"; do if (( opt >= REC_CPU )); then REAL_CPU=$opt; break; fi; done
for opt in "${CPU_OPTIONS[@]}"; do if (( opt >= IDEAL_CPU )); then REAL_IDEAL_CPU=$opt; break; fi; done

RAM_OPTIONS=(16 24 32 48 64 96 128 192 256 384 512)
for ram in "${RAM_OPTIONS[@]}"; do if (( ram >= REC_RAM )); then REAL_RAM=$ram; break; fi; done
for ram in "${RAM_OPTIONS[@]}"; do if (( ram >= IDEAL_RAM )); then REAL_IDEAL_RAM=$ram; break; fi; done

DISK_OPTIONS=(0.5 1 2 3 4 6 8 10 12 16 20 24 32 40 48 64)
for d in "${DISK_OPTIONS[@]}"; do if (( $(echo "$d >= $REC_DISK_TB" | bc -l) )); then REAL_DISK=$d; break; fi; done
for d in "${DISK_OPTIONS[@]}"; do if (( $(echo "$d >= $IDEAL_DISK_TB" | bc -l) )); then REAL_IDEAL_DISK=$d; break; fi; done

# ---------------- OUTPUT ----------------
echo -e "\n${BLUE}----- CURRENT SYSTEM -----${NC}"
echo -e "Host            : ${CYAN}$HOST${NC}"
echo -e "CPU             : ${CPU_CORES} cores (${CPU_MODEL})"
echo -e "Load            : ${LOAD_1} (${CPU_UTIL_PCT}% of capacity)"
echo -e "RAM             : ${USED_RAM_GB} / ${TOTAL_RAM_GB} GB (${RAM_USAGE_PCT}%)"
echo -e "Disk            : ${USED_DISK_TB} / ${TOTAL_DISK_TB} TB (${DISK_USAGE_PCT}%)"
echo -e "I/O             : ${IO_UTIL}%"
echo -e "Workload        : ${YELLOW}$TYPE${NC}"

if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    echo -e "cPanel Accounts : ${YELLOW}$CPANEL_ACCOUNTS${NC}"
fi

echo -e "\n${MAGENTA}----- RECOMMENDED HARDWARE -----${NC}"
echo -e "${CYAN}Standard:${NC}"
echo -e "  CPU : ${REAL_CPU} cores"
echo -e "  RAM : ${REAL_RAM} GB"
echo -e "  Disk: ${REAL_DISK} TB"

echo -e "\n${CYAN}Ideal:${NC}"
echo -e "  CPU : ${REAL_IDEAL_CPU} cores"
echo -e "  RAM : ${REAL_IDEAL_RAM} GB"
echo -e "  Disk: ${REAL_IDEAL_DISK} TB"

# ---------------- ALERTS ----------------
echo -e "\n${MAGENTA}----- NOTES -----${NC}"
if (( DISK_USAGE_PCT > 70 )); then
    echo -e "${YELLOW}⚠ Disk ${DISK_USAGE_PCT}% full - Upgrade recommended${NC}"
fi
if (( $(echo "$IO_UTIL > 70" | bc -l) )); then
    echo -e "${YELLOW}⚠ High I/O (${IO_UTIL}%) - Consider NVMe/SSD${NC}"
fi
if (( SWAP_USED > 0 )); then
    echo -e "${YELLOW}⚠ Swap in use - Memory pressure${NC}"
fi
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    echo -e "${CYAN}📊 Based on ${CPANEL_ACCOUNTS} cPanel accounts${NC}"
fi

echo ""
