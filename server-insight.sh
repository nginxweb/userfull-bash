#!/bin/bash
# =====================================================
# Script Name  : server-insight.sh
# Author       : Eric Smith
# Company      : ultahost.com
# Description  : Realistic hardware recommendations for hosting servers
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
LOAD_PER_CORE=$(echo "scale=2; $LOAD_1 / $CPU_CORES" | bc)
CPU_UTIL_PCT=$(echo "scale=1; ($LOAD_1 / $CPU_CORES) * 100" | bc)

# ---------------- RAM ----------------
read TOTAL_RAM_MB USED_RAM_MB <<< $(free -m | awk '/Mem:/ {print $2, $2-$7}')
AVAILABLE_RAM_MB=$(free -m | awk '/Mem:/ {print $7}')
TOTAL_RAM_GB=$(echo "scale=2; $TOTAL_RAM_MB / 1024" | bc)
USED_RAM_GB=$(echo "scale=2; $USED_RAM_MB / 1024" | bc)
AVAILABLE_RAM_GB=$(echo "scale=2; $AVAILABLE_RAM_MB / 1024" | bc)
SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')
RAM_USAGE_PCT=$(echo "scale=0; ($USED_RAM_MB * 100) / $TOTAL_RAM_MB" | bc)

# ---------------- DISK (Accurate from df -h) ----------------
# Get actual disk size from df -h (more accurate)
TOTAL_DISK_GB=$(df -BG --total | awk '/total/ {print $2}' | sed 's/G//')
USED_DISK_GB=$(df -BG --total | awk '/total/ {print $3}' | sed 's/G//')
TOTAL_DISK_TB=$(echo "scale=2; $TOTAL_DISK_GB / 1024" | bc)
USED_DISK_TB=$(echo "scale=2; $USED_DISK_GB / 1024" | bc)
DISK_USAGE_PCT=$(df --total | awk '/total/ {print $5}' | sed 's/%//')

# Get disk growth rate (check last 7 days if log exists)
if [ -f "/var/log/disk_usage.log" ]; then
    DISK_GROWTH_RATE=$(tail -n 7 /var/log/disk_usage.log | awk '{sum+=$1} END {print sum/7}')
else
    DISK_GROWTH_RATE=5  # Default 5% growth assumption
fi

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
RESELLER_ACCOUNTS=0
if [ -x "/usr/local/cpanel/cpanel" ]; then
  CPANEL_INSTALLED=1
  CPANEL_ACCOUNTS=$(whmapi1 listaccts 2>/dev/null | grep -c "user:" || echo 0)
  RESELLER_ACCOUNTS=$(whmapi1 listaccts 2>/dev/null | grep -B 10 "Reseller: 1" | grep "user:" | wc -l || echo 0)
fi

# =====================================================
# ========== HOSTING-OPTIMIZED RECOMMENDATIONS ==========
# =====================================================

# ---------- CPU RECOMMENDATION (Hosting servers) ----------
# Base rule for hosting: 1 core per 30-50 accounts minimum
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    MIN_CPU_FOR_ACCOUNTS=$(( (CPANEL_ACCOUNTS / 40) + 2 ))
else
    MIN_CPU_FOR_ACCOUNTS=2
fi

# Adjust based on load per core
if (( $(echo "$LOAD_PER_CORE > 1.2" | bc -l) )); then
    # Overloaded - need significant upgrade
    REC_CPU_MULT=1.5
    IDEAL_CPU_MULT=2.0
elif (( $(echo "$LOAD_PER_CORE > 0.8" | bc -l) )); then
    # Moderate load - some headroom
    REC_CPU_MULT=1.2
    IDEAL_CPU_MULT=1.5
else
    # Light load - maintain or slight upgrade
    REC_CPU_MULT=1.0
    IDEAL_CPU_MULT=1.25
fi

REC_CPU_CORES=$(echo "$CPU_CORES * $REC_CPU_MULT" | bc | awk '{print int($1)+1}')
IDEAL_CPU_CORES=$(echo "$CPU_CORES * $IDEAL_CPU_MULT" | bc | awk '{print int($1)+1}')

# Ensure minimum based on account count
if (( REC_CPU_CORES < MIN_CPU_FOR_ACCOUNTS )); then
    REC_CPU_CORES=$MIN_CPU_FOR_ACCOUNTS
fi
if (( IDEAL_CPU_CORES < MIN_CPU_FOR_ACCOUNTS + 4 )); then
    IDEAL_CPU_CORES=$((MIN_CPU_FOR_ACCOUNTS + 4))
fi

# Cap at reasonable maximum (no more than 3x current)
if (( REC_CPU_CORES > CPU_CORES * 3 )); then REC_CPU_CORES=$((CPU_CORES * 3)); fi
if (( IDEAL_CPU_CORES > CPU_CORES * 4 )); then IDEAL_CPU_CORES=$((CPU_CORES * 4)); fi

# ---------- RAM RECOMMENDATION (Hosting servers) ----------
# Rule of thumb for cPanel: 1-2GB per account + 8GB overhead
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    MIN_RAM_FOR_ACCOUNTS=$(( (CPANEL_ACCOUNTS / 1) + 8 ))  # 1GB per account
    RECOMMENDED_RAM_FOR_ACCOUNTS=$(( (CPANEL_ACCOUNTS * 2) + 8 ))  # 2GB per account
else
    MIN_RAM_FOR_ACCOUNTS=4
    RECOMMENDED_RAM_FOR_ACCOUNTS=8
fi

# Calculate based on current usage
if (( RAM_USAGE_PCT > 75 )); then
    REC_RAM_GB=$(echo "$USED_RAM_GB * 1.5" | bc)
    IDEAL_RAM_GB=$(echo "$USED_RAM_GB * 2.0" | bc)
elif (( RAM_USAGE_PCT > 50 )); then
    REC_RAM_GB=$(echo "$USED_RAM_GB * 1.25" | bc)
    IDEAL_RAM_GB=$(echo "$USED_RAM_GB * 1.75" | bc)
else
    REC_RAM_GB=$(echo "$TOTAL_RAM_GB * 1.2" | bc)
    IDEAL_RAM_GB=$(echo "$TOTAL_RAM_GB * 1.5" | bc)
fi

# Take the higher of usage-based or account-based recommendation
if (( $(echo "$MIN_RAM_FOR_ACCOUNTS > $REC_RAM_GB" | bc -l) )); then
    REC_RAM_GB=$MIN_RAM_FOR_ACCOUNTS
fi
if (( $(echo "$RECOMMENDED_RAM_FOR_ACCOUNTS > $IDEAL_RAM_GB" | bc -l) )); then
    IDEAL_RAM_GB=$RECOMMENDED_RAM_FOR_ACCOUNTS
fi

# ---------- DISK RECOMMENDATION (Hosting servers - CRITICAL) ----------
# For hosting, disk needs are based on:
# 1. Current usage + growth
# 2. Number of accounts (each account may need 10-50GB)
# 3. Type of hosting (shared/reseller)

# Calculate minimum disk per account (10GB minimum for shared hosting)
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    MIN_DISK_PER_ACCOUNT_GB=15
    IDEAL_DISK_PER_ACCOUNT_GB=30
    
    MIN_DISK_BY_ACCOUNTS_GB=$((CPANEL_ACCOUNTS * MIN_DISK_PER_ACCOUNT_GB))
    IDEAL_DISK_BY_ACCOUNTS_GB=$((CPANEL_ACCOUNTS * IDEAL_DISK_PER_ACCOUNT_GB))
else
    MIN_DISK_BY_ACCOUNTS_GB=100
    IDEAL_DISK_BY_ACCOUNTS_GB=200
fi

# Calculate based on current usage with growth factor
if (( DISK_USAGE_PCT > 80 )); then
    GROWTH_FACTOR=2.5
elif (( DISK_USAGE_PCT > 65 )); then
    GROWTH_FACTOR=2.0
elif (( DISK_USAGE_PCT > 50 )); then
    GROWTH_FACTOR=1.5
else
    GROWTH_FACTOR=1.3
fi

# Add growth rate factor (if disk is growing fast, need more space)
if (( $(echo "$DISK_GROWTH_RATE > 10" | bc -l) )); then
    GROWTH_FACTOR=$(echo "$GROWTH_FACTOR * 1.3" | bc)
fi

REC_DISK_BY_USAGE_GB=$(echo "$USED_DISK_GB * $GROWTH_FACTOR" | bc)
IDEAL_DISK_BY_USAGE_GB=$(echo "$USED_DISK_GB * $GROWTH_FACTOR * 1.5" | bc)

# Take the HIGHER of usage-based or account-based recommendation
if (( $(echo "$MIN_DISK_BY_ACCOUNTS_GB > $REC_DISK_BY_USAGE_GB" | bc -l) )); then
    REC_DISK_GB=$MIN_DISK_BY_ACCOUNTS_GB
else
    REC_DISK_GB=$REC_DISK_BY_USAGE_GB
fi

if (( $(echo "$IDEAL_DISK_BY_ACCOUNTS_GB > $IDEAL_DISK_BY_USAGE_GB" | bc -l) )); then
    IDEAL_DISK_GB=$IDEAL_DISK_BY_ACCOUNTS_GB
else
    IDEAL_DISK_GB=$IDEAL_DISK_BY_USAGE_GB
fi

# Ensure at least current total disk + 50% headroom
MIN_DISK_GB=$(echo "$TOTAL_DISK_GB * 1.5" | bc)
if (( $(echo "$REC_DISK_GB < $MIN_DISK_GB" | bc -l) )); then
    REC_DISK_GB=$MIN_DISK_GB
fi

# Convert to TB for display
REC_DISK_TB=$(echo "scale=2; $REC_DISK_GB / 1024" | bc)
IDEAL_DISK_TB=$(echo "scale=2; $IDEAL_DISK_GB / 1024" | bc)

# Cap disk at reasonable maximum (no more than 10x current for hosting)
if (( $(echo "$IDEAL_DISK_TB > $TOTAL_DISK_TB * 10" | bc -l) )); then
    IDEAL_DISK_TB=$(echo "$TOTAL_DISK_TB * 8" | bc)
fi

# ---------------- REALISTIC HARDWARE (Market Available) ----------------
CPU_OPTIONS=(4 6 8 12 16 20 24 32 40 48 64 80 96)
for opt in "${CPU_OPTIONS[@]}"; do if (( opt >= REC_CPU_CORES )); then REAL_REC_CPU=$opt; break; fi; done
for opt in "${CPU_OPTIONS[@]}"; do if (( opt >= IDEAL_CPU_CORES )); then REAL_IDEAL_CPU=$opt; break; fi; done

RAM_OPTIONS=(16 24 32 48 64 96 128 192 256 384 512 768 1024)
REC_RAM_INT=$(echo "$REC_RAM_GB" | awk '{print int($1)}')
IDEAL_RAM_INT=$(echo "$IDEAL_RAM_GB" | awk '{print int($1)}')
for ram in "${RAM_OPTIONS[@]}"; do if (( ram >= REC_RAM_INT )); then REAL_REC_RAM=$ram; break; fi; done
for ram in "${RAM_OPTIONS[@]}"; do if (( ram >= IDEAL_RAM_INT )); then REAL_IDEAL_RAM=$ram; break; fi; done

DISK_OPTIONS=(0.5 1 2 3 4 6 8 10 12 16 20 24 30 32 40 48 64 80 96 128)
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

if (( CPANEL_INSTALLED )); then
    echo -e "\n${MAGENTA}----- CPANEL ANALYSIS -----${NC}"
    echo -e "Total Accounts  : ${YELLOW}$CPANEL_ACCOUNTS${NC}"
    echo -e "Resellers       : ${YELLOW}$RESELLER_ACCOUNTS${NC}"
    echo -e "${CYAN}Hosting Requirements:${NC}"
    echo -e "  • Minimum CPU  : ${MIN_CPU_FOR_ACCOUNTS} cores (1 per 40 accounts)"
    echo -e "  • Minimum RAM  : ${MIN_RAM_FOR_ACCOUNTS} GB (1GB per account)"
    echo -e "  • Recommended RAM: ${RECOMMENDED_RAM_FOR_ACCOUNTS} GB (2GB per account)"
    echo -e "  • Minimum Disk : ${MIN_DISK_BY_ACCOUNTS_GB} GB (${MIN_DISK_BY_ACCOUNTS_GB} / 1024 = $(echo "scale=1; $MIN_DISK_BY_ACCOUNTS_GB / 1024" | bc) TB)"
    echo -e "  • Recommended Disk: ${IDEAL_DISK_BY_ACCOUNTS_GB} GB ($(echo "scale=1; $IDEAL_DISK_BY_ACCOUNTS_GB / 1024" | bc) TB)"
fi

echo -e "\n${MAGENTA}----- REALISTIC RECOMMENDATION -----${NC}"
echo -e "${CYAN}Recommended Config (Now - 6 months):${NC}"
echo -e "CPU Cores : $REAL_REC_CPU (Current: $CPU_CORES) $(if (( REAL_REC_CPU > CPU_CORES )); then echo "✓ Upgrade"; else echo "= OK"; fi)"
echo -e "RAM       : ${REAL_REC_RAM} GB (Current: ${TOTAL_RAM_GB} GB) $(if (( REAL_REC_RAM > $(echo $TOTAL_RAM_GB | cut -d. -f1) )); then echo "✓ Upgrade"; else echo "= OK"; fi)"
echo -e "Disk      : ${REAL_REC_DISK} TB (Current: ${TOTAL_DISK_TB} TB) $(if (( $(echo "$REAL_REC_DISK > $TOTAL_DISK_TB" | bc -l) )); then echo "✓ Upgrade"; else echo "= OK"; fi)"

echo -e "\n${CYAN}Ideal Config (6-12 months growth):${NC}"
echo -e "CPU Cores : $REAL_IDEAL_CPU"
echo -e "RAM       : ${REAL_IDEAL_RAM} GB"
echo -e "Disk      : ${REAL_IDEAL_DISK} TB"

echo -e "\n${MAGENTA}===== EXECUTIVE SUMMARY =====${NC}"
echo -e "Server Type     : ${YELLOW}$TYPE${NC}"
echo -e "Load Status     : $(if (( $(echo "$LOAD_PER_CORE < 0.5" | bc -l) )); then echo "${GREEN}LOW${NC}"; elif (( $(echo "$LOAD_PER_CORE < 0.8" | bc -l) )); then echo "${YELLOW}MODERATE${NC}"; else echo "${RED}HIGH${NC}"; fi)"
echo -e "RAM Status      : ${RAM_STATUS}$RAM_TEXT${NC}"
echo -e "Disk Status     : ${DISK_STATUS}$DISK_TEXT${NC}"

if (( SWAP_USED > 0 )); then
  echo -e "${RED}⚠ Swap in use → Memory pressure detected${NC}"
fi

if (( DISK_USAGE_PCT > 85 )); then
  echo -e "${RED}⚠ Disk nearing capacity! Current usage: ${DISK_USAGE_PCT}%${NC}"
elif (( DISK_USAGE_PCT > 70 )); then
  echo -e "${YELLOW}⚠ Disk usage is high (${DISK_USAGE_PCT}%). Plan upgrade soon${NC}"
fi

if (( $(echo "$IO_UTIL > 80" | bc -l) )); then
  echo -e "${RED}⚠ Very high I/O (${IO_UTIL}%). Consider NVMe/SSD upgrade${NC}"
elif (( $(echo "$IO_UTIL > 60" | bc -l) )); then
  echo -e "${YELLOW}⚠ High I/O (${IO_UTIL}%). Consider faster storage${NC}"
fi

echo -e "\n${CYAN}===== RECOMMENDED SERVER CONFIGURATIONS =====${NC}"
echo -e "${GREEN}Budget Option:${NC}"
echo -e "  • CPU: ${REAL_REC_CPU} cores"
echo -e "  • RAM: ${REAL_REC_RAM} GB DDR4"
echo -e "  • Disk: ${REAL_REC_DISK} TB NVMe/SSD"
echo -e "  • RAID: RAID-10 recommended"

echo -e "\n${GREEN}Performance Option:${NC}"
echo -e "  • CPU: ${REAL_IDEAL_CPU} cores"
echo -e "  • RAM: ${REAL_IDEAL_RAM} GB DDR5"
echo -e "  • Disk: ${REAL_IDEAL_DISK} TB NVMe (Enterprise)"
echo -e "  • RAID: RAID-10 with hot spare"

# ---------------- HTML OUTPUT (simplified) ----------------
HTML_FILE="${HOST}_report.html"
cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Server Report - $HOST</title>
<style>
body{font-family:Arial;background:#f9f9f9;margin:20px;}
h1{color:#2c3e50;} .upgrade{color:green;} .warning{color:orange;} .critical{color:red;}
table{border-collapse:collapse;width:100%;} th,td{border:1px solid #ddd;padding:8px;}
th{background:#2980b9;color:white;}
</style>
</head>
<body>
<h1>Server Insight Report - $HOST</h1>
<h2>Current vs Recommended</h2>
<table>
<tr><th>Component</th><th>Current</th><th>Recommended</th><th>Ideal</th></tr>
<tr><td>CPU Cores</td><td>$CPU_CORES</td><td>$REAL_REC_CPU</td><td>$REAL_IDEAL_CPU</td></tr>
<tr><td>RAM (GB)</td><td>${TOTAL_RAM_GB}</td><td>${REAL_REC_RAM}</td><td>${REAL_IDEAL_RAM}</td></tr>
<tr><td>Disk (TB)</td><td>${TOTAL_DISK_TB}</td><td>${REAL_REC_DISK}</td><td>${REAL_IDEAL_DISK}</td></tr>
</table>
EOF

echo -e "\n${GREEN}HTML report: $(realpath "$HTML_FILE")${NC}"
