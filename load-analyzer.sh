#!/bin/bash
# Linux Load & Resource Analyzer (Cross-distro, fixed for awk issues)

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${CYAN}===== Linux Load Analyzer =====${RESET}"
echo -e "Time: $(date)"
echo -e "Host: $(hostname)"
echo ""

# Load
load1=$(awk '{print $1}' /proc/loadavg)
cores=$(nproc)
echo -e "Load (1 min): $load1"
echo -e "CPU cores: $cores"
if (( $(echo "$load1 > $cores" | bc -l) )); then
    echo -e "${RED}⚠️ Load is high${RESET}"
else
    echo -e "${GREEN}✅ Load is within normal range${RESET}"
fi
echo ""

# Top CPU processes
echo -e "${CYAN}---- Top CPU Processes ----${RESET}"
ps -eo pid,user,comm,%cpu,%mem,etime,nlwp --sort=-%cpu | head -n 10 | awk '{printf "  PID:%-6s User:%-10s Cmd:%-15s CPU:%5s%% MEM:%5s%% Time:%-12s Threads:%s\n",$1,$2,$3,$4,$5,$6,$7}'

echo ""
# Memory & Swap
echo -e "${CYAN}---- Memory & Swap ----${RESET}"
free -h
swap_used=$(free | awk '/Swap/ {print $3}')
if [[ "$swap_used" -gt 0 ]]; then
    echo -e "${YELLOW}⚠️ Swap in use → possible memory pressure${RESET}"
fi
echo ""

# Run queue
rqueue=$(cat /proc/loadavg | awk '{print $1}')
blocked=$(ps -eo state | grep -c D)
echo -e "${CYAN}---- Run Queue ----${RESET}"
echo -e "Run queue (r): $rqueue Blocked (b): $blocked"
echo ""

# Disk I/O
echo -e "${CYAN}---- Disk I/O ----${RESET}"
if command -v iostat &>/dev/null; then
    iostat -dx 1 2 | awk 'NR>6{printf "%-6s util:%5s%% await:%6s ms\n",$1,$NF,$14}' | head -n -1
else
    echo "iostat not installed, skipping Disk I/O"
fi
echo ""

# CPU usage
echo -e "${CYAN}---- CPU Usage ----${RESET}"
if command -v mpstat &>/dev/null; then
    mpstat 1 1 | awk 'NR>3 {printf "User:%5s%% System:%5s%% IOwait:%5s%% Idle:%5s%%\n",$3,$5,$6,$12}'
fi
echo ""

# Determine primary cause
cpu_top=$(ps -eo %cpu --sort=-%cpu | sed -n '2p' | tr -d ' ')
mem_used=$(free | awk '/Mem/ {printf "%.0f", $3/$2*100}')
swap_used_percent=$(free | awk '/Swap/ {if($2>0) printf "%.0f", $3/$2*100; else print 0}')

echo -e "${CYAN}---- Conclusion ----${RESET}"
if (( $(echo "$cpu_top > 50" | bc -l) )); then
    echo -e "${RED}Primary cause: High CPU usage by processes${RESET}\n"
    ps -eo pid,user,comm,%cpu,%mem,etime,nlwp --sort=-%cpu | head -n 10 | \
    awk '{printf "  PID:%-6s User:%-10s Cmd:%-15s CPU:%5s%% MEM:%5s%% Time:%-12s Threads:%s\n",$1,$2,$3,$4,$5,$6,$7}'
elif (( mem_used > 80 )); then
    echo -e "${RED}Primary cause: High Memory usage${RESET}\n"
    ps -eo pid,user,comm,%mem,%cpu,etime,nlwp --sort=-%mem | head -n 10 | \
    awk '{printf "  PID:%-6s User:%-10s Cmd:%-15s MEM:%5s%% CPU:%5s%% Time:%-12s Threads:%s\n",$1,$2,$3,$4,$5,$6,$7}'
elif (( swap_used_percent > 10 )); then
    echo -e "${RED}Primary cause: Memory pressure / swapping${RESET}\n"
    for pid in $(ls /proc | grep -E '^[0-9]+$'); do
        swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
        if [[ -n "$swap_kb" && "$swap_kb" -gt 0 ]]; then
            cmd=$(ps -p $pid -o comm=)
            user=$(ps -p $pid -o user=)
            echo "  PID:$pid User:$user CMD:$cmd Swap:${swap_kb}KB"
        fi
    done
else
    echo -e "${GREEN}Primary cause: Normal${RESET}"
fi
echo -e "${CYAN}==============================${RESET}"
