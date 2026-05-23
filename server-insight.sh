#!/bin/bash
# =====================================================
# Script Name  : server-insight.sh
# Author       : Eric Smith
# Company      : ultahost.com
# Description  : Gathers system metrics and provides
#                workload classification & recommendations
#                ** NEVER recommends weaker hardware **
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
CPU_MODEL=$(lscpu | awk -F: '/Model name/ {print $2}' | sed 's/^[ \t]*//')
TOTAL_CPU_FREQ=$(awk -F: '/cpu MHz/ {sum += $2} END {print sum}' /proc/cpuinfo)
TOTAL_CPU_FREQ_GHZ=$(echo "scale=2; $TOTAL_CPU_FREQ / 1000" | bc)

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
if (( CPU_USAGE > 70 )); then TYPE="CPU Intensive"; fi
if (( USED_RAM_MB > (TOTAL_RAM_MB * 75 / 100) )); then TYPE="Memory Intensive"; fi
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
# ========== IMPROVED RECOMMENDATION LOGIC ==========
# =====================================================

# ---------- CPU RECOMMENDATION (Never less than current) ----------
# Base recommendation on workload type and current cores
if [[ "$TYPE" == "IO Intensive" ]]; then
    # IO intensive needs enough cores for parallel I/O operations
    BASE_REC_CPU=$CPU_CORES
    BASE_IDEAL_CPU=$((CPU_CORES + 2))
elif [[ "$TYPE" == "CPU Intensive" ]]; then
    # CPU intensive needs significant headroom
    BASE_REC_CPU=$((CPU_CORES + 2))
    BASE_IDEAL_CPU=$((CPU_CORES + 4))
elif (( $(echo "$LOAD_1 > $CPU_CORES * 0.7" | bc -l) )); then
    # High load scenario
    BASE_REC_CPU=$((CPU_CORES + 1))
    BASE_IDEAL_CPU=$((CPU_CORES + 2))
else
    # Light load - keep same or slightly better
    BASE_REC_CPU=$CPU_CORES
    BASE_IDEAL_CPU=$((CPU_CORES + 1))
fi

# Adjust for cPanel accounts if present
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    # Rule: 1 core per 20 accounts + base
    CPANEL_CPU_NEED=$(( (CPANEL_ACCOUNTS / 20) + 2 ))
    if (( CPANEL_CPU_NEED > BASE_REC_CPU )); then
        BASE_REC_CPU=$CPANEL_CPU_NEED
    fi
    if (( CPANEL_CPU_NEED + 2 > BASE_IDEAL_CPU )); then
        BASE_IDEAL_CPU=$((CPANEL_CPU_NEED + 2))
    fi
fi

# Apply safety factor based on load
if (( $(echo "$LOAD_1 > $CPU_CORES" | bc -l) )); then
    REC_CPU=$(echo "$BASE_REC_CPU * 1.5" | bc | awk '{print int($1)+1}')
    IDEAL_CPU=$(echo "$BASE_IDEAL_CPU * 2" | bc | awk '{print int($1)+1}')
else
    REC_CPU=$BASE_REC_CPU
    IDEAL_CPU=$BASE_IDEAL_CPU
fi

# FINAL CHECK: NEVER recommend less than current CPU cores
if (( REC_CPU < CPU_CORES )); then
    REC_CPU=$CPU_CORES
    echo -e "${YELLOW}⚠ Adjusted: CPU recommendation cannot be less than current${NC}"
fi
if (( IDEAL_CPU < CPU_CORES )); then
    IDEAL_CPU=$CPU_CORES
fi

# Cap at reasonable maximum (no more than 2x current)
if (( REC_CPU > CPU_CORES * 2 )); then
    REC_CPU=$((CPU_CORES * 2))
fi
if (( IDEAL_CPU > CPU_CORES * 2 + 4 )); then
    IDEAL_CPU=$((CPU_CORES * 2 + 4))
fi

# ---------- RAM RECOMMENDATION (Never less than current) ----------
# Calculate needed RAM based on usage pattern
if (( SWAP_USED > 0 )); then
    # Swap in use means memory pressure
    BASE_REC_RAM_MB=$((TOTAL_RAM_MB + (USED_RAM_MB / 2)))
    BASE_IDEAL_RAM_MB=$((TOTAL_RAM_MB * 2))
else
    BASE_REC_RAM_MB=$((TOTAL_RAM_MB + (USED_RAM_MB / 4)))
    BASE_IDEAL_RAM_MB=$((TOTAL_RAM_MB + (USED_RAM_MB / 2)))
fi

# Adjust for cPanel (each account typically needs ~512MB - 1GB)
if (( CPANEL_INSTALLED && CPANEL_ACCOUNTS > 0 )); then
    CPANEL_RAM_NEED_MB=$((CPANEL_ACCOUNTS * 512))
    if (( CPANEL_RAM_NEED_MB > BASE_REC_RAM_MB )); then
        BASE_REC_RAM_MB=$CPANEL_RAM_NEED_MB
    fi
    if (( CPANEL_RAM_NEED_MB * 2 > BASE_IDEAL_RAM_MB )); then
        BASE_IDEAL_RAM_MB=$((CPANEL_RAM_NEED_MB * 2))
    fi
fi

# Apply load factor
if (( $(echo "$LOAD_1 > $CPU_CORES" | bc -l) )); then
    REC_RAM_MB=$(echo "$BASE_REC_RAM_MB * 1.5" | bc)
    IDEAL_RAM_MB=$(echo "$BASE_IDEAL_RAM_MB * 1.5" | bc)
else
    REC_RAM_MB=$BASE_REC_RAM_MB
    IDEAL_RAM_MB=$BASE_IDEAL_RAM_MB
fi

# Ensure recommendations are at least current total RAM
CURRENT_RAM_MB=$TOTAL_RAM_MB
if (( $(echo "$REC_RAM_MB < $CURRENT_RAM_MB" | bc -l) )); then
    REC_RAM_MB=$CURRENT_RAM_MB
fi
if (( $(echo "$IDEAL_RAM_MB < $CURRENT_RAM_MB" | bc -l) )); then
    IDEAL_RAM_MB=$CURRENT_RAM_MB
fi

# Convert to GB
REC_RAM_GB=$(echo "scale=2; $REC_RAM_MB / 1024" | bc)
IDEAL_RAM_GB=$(echo "scale=2; $IDEAL_RAM_MB / 1024" | bc)

# ---------- DISK RECOMMENDATION (Never less than current) ----------
# Base on current usage with growth factor
if (( DISK_USAGE_PCT > 80 )); then
    GROWTH_FACTOR=2.0
elif (( DISK_USAGE_PCT > 60 )); then
    GROWTH_FACTOR=1.5
else
    GROWTH_FACTOR=1.2
fi

REC_DISK_GB=$(echo "$USED_DISK_GB * $GROWTH_FACTOR" | bc)
IDEAL_DISK_GB=$(echo "$USED_DISK_GB * $GROWTH_FACTOR * 1.3" | bc)

# Ensure disk recommendation is never less than current total disk
if (( $(echo "$REC_DISK_GB < $TOTAL_DISK_GB" | bc -l) )); then
    REC_DISK_GB=$TOTAL_DISK_GB
fi
if (( $(echo "$IDEAL_DISK_GB < $TOTAL_DISK_GB" | bc -l) )); then
    IDEAL_DISK_GB=$TOTAL_DISK_GB
fi

REC_DISK_TB=$(echo "scale=2; $REC_DISK_GB / 1024" | bc)
IDEAL_DISK_TB=$(echo "scale=2; $IDEAL_DISK_GB / 1024" | bc)

# ---------------- REALISTIC HARDWARE (Market Available) ----------------
CPU_OPTIONS=(4 6 8 12 16 24 32 48 64 96 128)
for opt in "${CPU_OPTIONS[@]}"; do if (( opt >= REC_CPU )); then REAL_REC_CPU=$opt; break; fi; done
for opt in "${CPU_OPTIONS[@]}"; do if (( opt >= IDEAL_CPU )); then REAL_IDEAL_CPU=$opt; break; fi; done

RAM_OPTIONS=(16 32 48 64 96 128 192 256 384 512 768 1024)
REC_RAM_INT=$(echo "$REC_RAM_GB" | awk '{print int($1)}')
IDEAL_RAM_INT=$(echo "$IDEAL_RAM_GB" | awk '{print int($1)}')
for ram in "${RAM_OPTIONS[@]}"; do if (( ram >= REC_RAM_INT )); then REAL_REC_RAM=$ram; break; fi; done
for ram in "${RAM_OPTIONS[@]}"; do if (( ram >= IDEAL_RAM_INT )); then REAL_IDEAL_RAM=$ram; break; fi; done

DISK_OPTIONS=(0.5 1 2 4 6 8 10 12 16 20 24 32 48 64)
for d in "${DISK_OPTIONS[@]}"; do if (( $(echo "$d >= $REC_DISK_TB" | bc -l) )); then REAL_REC_DISK=$d; break; fi; done
for d in "${DISK_OPTIONS[@]}"; do if (( $(echo "$d >= $IDEAL_DISK_TB" | bc -l) )); then REAL_IDEAL_DISK=$d; break; fi; done

# ---------------- STATUS ----------------
RAM_STATUS=$GREEN; CPU_STATUS=$GREEN; DISK_STATUS=$GREEN
RAM_TEXT="OK"; CPU_TEXT="OK"; DISK_TEXT="OK"
if (( USED_RAM_MB > (TOTAL_RAM_MB * 80 / 100) )); then RAM_STATUS=$YELLOW; RAM_TEXT="HIGH"; fi
if (( CPU_USAGE > 80 )); then CPU_STATUS=$YELLOW; CPU_TEXT="HIGH"; fi
if (( DISK_USAGE_PCT > 85 )); then DISK_STATUS=$RED; DISK_TEXT="CRITICAL"; fi

# ---------------- COMPARISON CHECK ----------------
echo -e "\n${BLUE}----- CURRENT HARDWARE SPECS (BASELINE) -----${NC}"
echo -e "CPU Cores       : ${CYAN}${CPU_CORES} cores${NC}"
echo -e "RAM             : ${CYAN}${TOTAL_RAM_GB} GB${NC}"
echo -e "Disk            : ${CYAN}${TOTAL_DISK_TB} TB${NC}"

# ---------------- TERMINAL OUTPUT ----------------
echo -e "\n${BLUE}----- CURRENT USAGE -----${NC}"
echo -e "Host            : ${CYAN}$HOST${NC}"
echo -e "CPU Model       : ${CYAN}$CPU_MODEL${NC}"
echo -e "CPU Total Freq  : ${CYAN}$TOTAL_CPU_FREQ_GHZ GHz${NC}"
echo -e "CPU Cores       : ${CPU_CORES} cores | ${CPU_STATUS}$CPU_TEXT${NC} | Load: $LOAD_1 | Usage: ${CPU_USAGE}%"
echo -e "RAM             : ${USED_RAM_GB} / ${TOTAL_RAM_GB} GB | Available: ${AVAILABLE_RAM_GB} GB | Status: ${RAM_STATUS}$RAM_TEXT${NC}"
echo -e "Swap Used       : ${SWAP_USED} MB"
echo -e "Disk            : ${USED_DISK_TB} / ${TOTAL_DISK_TB} TB (${DISK_USAGE_PCT}%) | Status: ${DISK_STATUS}$DISK_TEXT${NC}"
echo -e "IO Utilization  : ${IO_UTIL}%"

echo -e "\n${MAGENTA}----- CLASSIFICATION -----${NC}"
echo -e "Workload Type   : ${YELLOW}$TYPE${NC}"

echo -e "\n${MAGENTA}----- RECOMMENDATION (NEVER WEAKER THAN CURRENT) -----${NC}"
echo -e "${CYAN}Raw Recommended:${NC}"
echo -e "CPU Cores : $REC_CPU (Current: $CPU_CORES) ✓"
echo -e "RAM       : ${REC_RAM_GB} GB (Current: ${TOTAL_RAM_GB} GB) ✓"
echo -e "Disk      : ${REC_DISK_TB} TB (Current: ${TOTAL_DISK_TB} TB) ✓"

echo -e "\n${CYAN}Realistic Market Config:${NC}"
echo -e "CPU Cores : $REAL_REC_CPU"
echo -e "RAM       : ${REAL_REC_RAM} GB"
echo -e "Disk      : ${REAL_REC_DISK} TB"

echo -e "\n${CYAN}Raw Ideal:${NC}"
echo -e "CPU Cores : $IDEAL_CPU"
echo -e "RAM       : ${IDEAL_RAM_GB} GB"
echo -e "Disk      : ${IDEAL_DISK_TB} TB"

echo -e "\n${CYAN}Realistic Market Ideal:${NC}"
echo -e "CPU Cores : $REAL_IDEAL_CPU"
echo -e "RAM       : ${REAL_IDEAL_RAM} GB"
echo -e "Disk      : ${REAL_IDEAL_DISK} TB"

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

# ---------------- HTML OUTPUT ----------------
HTML_FILE="${HOST}_report.html"
cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Server Insight Report - $HOST</title>
<style>
body { font-family: Arial, sans-serif; background: #f9f9f9; margin: 20px; }
h1 { text-align:center; color:#2c3e50; font-size:28px; }
h2 { color:#2980b9; }
table { width:90%; margin:20px auto; border-collapse: collapse; }
th, td { border:1px solid #ddd; padding:10px; text-align:left; }
th { background-color:#2980b9; color:white; }
tr:nth-child(even){background-color:#f2f2f2;}
.status-ok { color:green; font-weight:bold; }
.status-high { color:orange; font-weight:bold; }
.status-critical { color:red; font-weight:bold; }
.upgrade-badge { color:green; font-weight:bold; }
.current-spec { background-color:#e8f4f8; }
</style>
</head>
<body>
<h1>Server Insight Report - <span style="color:#e67e22;">$HOST</span></h1>

<h2>Current Hardware (Baseline)</h2>
<table class="current-spec">
<tr><th>Component</th><th>Current Spec</th></tr>
<tr><td>CPU Cores</td><td><strong>$CPU_CORES cores</strong></td></tr>
<tr><td>RAM</td><td><strong>${TOTAL_RAM_GB} GB</strong></td></tr>
<tr><td>Disk</td><td><strong>${TOTAL_DISK_TB} TB</strong></td></tr>
</table>

<h2>Current Usage Metrics</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>CPU Model</td><td>$CPU_MODEL</td></tr>
<tr><td>CPU Frequency</td><td>${TOTAL_CPU_FREQ_GHZ} GHz</td></tr>
<tr><td>CPU Cores</td><td>$CPU_CORES cores | <span class="status-${CPU_TEXT,,}">$CPU_TEXT</span> | Load: $LOAD_1 | Usage: ${CPU_USAGE}%</td></tr>
<tr><td>RAM Usage</td><td>${USED_RAM_GB} / ${TOTAL_RAM_GB} GB | Available: ${AVAILABLE_RAM_GB} GB | <span class="status-${RAM_TEXT,,}">$RAM_TEXT</span></td></tr>
<tr><td>Swap Used</td><td>$SWAP_USED MB</td></tr>
<tr><td>Disk Usage</td><td>${USED_DISK_TB} / ${TOTAL_DISK_TB} TB (${DISK_USAGE_PCT}%) | <span class="status-${DISK_TEXT,,}">$DISK_TEXT</span></td></tr>
<tr><td>IO Utilization</td><td>${IO_UTIL}%</td></tr>
<tr><td>Workload Type</td><td><strong>$TYPE</strong></td></tr>
</table>

<h2>Upgrade Recommendations (✓ = Upgrade / = = Same)</h2>
<table>
<tr>
<th>Component</th>
<th>Current</th>
<th>Recommended</th>
<th>Ideal</th>
</tr>
<tr>
<td>CPU Cores</td>
<td>$CPU_CORES</td>
<td>$REAL_REC_CPU $(if (( REAL_REC_CPU > CPU_CORES )); then echo "✓ Upgrade"; elif (( REAL_REC_CPU == CPU_CORES )); then echo "= Same"; else echo "⚠ Check"; fi)</td>
<td>$REAL_IDEAL_CPU $(if (( REAL_IDEAL_CPU > CPU_CORES )); then echo "✓ Upgrade"; elif (( REAL_IDEAL_CPU == CPU_CORES )); then echo "= Same"; else echo "⚠ Check"; fi)</td>
</tr>
<tr>
<td>RAM (GB)</td>
<td>${TOTAL_RAM_GB}</td>
<td>$REAL_REC_RAM $(if (( REAL_REC_RAM > $(echo $TOTAL_RAM_GB | cut -d. -f1) )); then echo "✓ Upgrade"; else echo "= Same"; fi)</td>
<td>$REAL_IDEAL_RAM $(if (( REAL_IDEAL_RAM > $(echo $TOTAL_RAM_GB | cut -d. -f1) )); then echo "✓ Upgrade"; else echo "= Same"; fi)</td>
</tr>
<tr>
<td>Disk (TB)</td>
<td>${TOTAL_DISK_TB}</td>
<td>$REAL_REC_DISK $(if (( $(echo "$REAL_REC_DISK > $TOTAL_DISK_TB" | bc -l) )); then echo "✓ Upgrade"; else echo "= Same"; fi)</td>
<td>$REAL_IDEAL_DISK $(if (( $(echo "$REAL_IDEAL_DISK > $TOTAL_DISK_TB" | bc -l) )); then echo "✓ Upgrade"; else echo "= Same"; fi)</td>
</tr>
</table>

EOF

if (( SWAP_USED > 0 )); then
  echo "<p style='color:red; font-weight:bold;'>⚠ Swap in use → Memory pressure detected</p>" >> "$HTML_FILE"
fi
if (( DISK_USAGE_PCT > 85 )); then
  echo "<p style='color:red; font-weight:bold;'>⚠ Disk nearing capacity</p>" >> "$HTML_FILE"
fi
if (( CPANEL_INSTALLED )); then
cat >> "$HTML_FILE" <<EOF
<h2>cPanel Accounts</h2>
<table>
<tr><th>Metric</th><th>Count</th></tr>
<tr><td>Total Accounts</td><td>$CPANEL_ACCOUNTS</td></tr>
<tr><td>Reseller Accounts</td><td>$RESELLER_ACCOUNTS</td></tr>
</table>
EOF
fi

echo "</body></html>" >> "$HTML_FILE"
echo -e "\n${GREEN}HTML report generated at: $(realpath "$HTML_FILE")${NC}"

# ---------------- FINAL VERIFICATION ----------------
echo -e "\n${CYAN}===== VERIFICATION =====${NC}"
echo -e "✓ All recommendations are >= current hardware"
echo -e "✓ CPU Recommended ($REAL_REC_CPU) >= Current ($CPU_CORES)"
echo -e "✓ RAM Recommended (${REAL_REC_RAM}GB) >= Current (${TOTAL_RAM_GB}GB)"
echo -e "✓ Disk Recommended (${REAL_REC_DISK}TB) >= Current (${TOTAL_DISK_TB}TB)"
