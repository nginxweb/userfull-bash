#!/bin/bash

# Ultahost Server Hardware Report
# Author: Eric Smith
# Company: Ultahost
# Version: 1.1

# Colors for display
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'
LINE="================================================"

# Install prerequisites
install_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    fi
    
    # Check and install required tools
    if ! command -v dmidecode &> /dev/null; then
        echo -e "${YELLOW}Installing dmidecode...${NC}"
        case $OS in
            ubuntu|debian)
                apt-get update > /dev/null 2>&1
                apt-get install -y dmidecode > /dev/null 2>&1
                ;;
            centos|rhel|almalinux)
                if command -v yum &> /dev/null; then
                    yum install -y dmidecode > /dev/null 2>&1
                elif command -v dnf &> /dev/null; then
                    dnf install -y dmidecode > /dev/null 2>&1
                fi
                ;;
        esac
    fi
    
    echo -e "${GREEN}Ready to collect hardware information...${NC}"
}

# Function for df compatibility
show_disk_usage() {
    # Try different df formats
    if df --help 2>&1 | grep -q '\-\-output'; then
        # Try with mountpoint field (some systems use mountpoint, some mountpoint)
        if df --help 2>&1 | grep -q 'mountpoint'; then
            df -h --output=source,size,used,avail,pcent,mountpoint | grep -E '^/dev/' | head -5
        else
            df -h | grep -E '^/dev/' | head -5
        fi
    else
        # Simple df format for older systems
        df -h | grep -E '^/dev/' | head -5
    fi
}

# Display banner
echo -e "${BLUE}${BOLD}${LINE}${NC}"
echo -e "${BLUE}${BOLD}ULTALINUX SERVER HARDWARE REPORT${NC}"
echo -e "${BLUE}${BOLD}${LINE}${NC}"
echo -e "${YELLOW}Author: Eric Smith | Company: Ultahost${NC}\n"

# Install prerequisites
install_prerequisites

echo -e "${YELLOW}Collecting hardware information (5 seconds)...${NC}\n"
sleep 5

# 1. CPU SPECIFICATIONS
echo -e "${GREEN}${BOLD}[1] CPU SPECIFICATIONS${NC}"
echo -e "${LINE}"
if [ -f /proc/cpuinfo ]; then
    echo -e "Model: ${YELLOW}$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)${NC}"
    echo -e "Cores: ${YELLOW}$(grep -c '^processor' /proc/cpuinfo)${NC}"
    echo -e "Architecture: ${YELLOW}$(uname -m)${NC}"
    echo -e "CPU MHz: ${YELLOW}$(grep -m1 'cpu MHz' /proc/cpuinfo | cut -d: -f2 | xargs)${NC}"
    
    # Get threads per core correctly
    siblings=$(grep -m1 'siblings' /proc/cpuinfo | cut -d: -f2 | xargs)
    cpu_cores=$(grep -m1 'cpu cores' /proc/cpuinfo | cut -d: -f2 | xargs)
    if [ -n "$siblings" ] && [ -n "$cpu_cores" ] && [ "$cpu_cores" -ne 0 ]; then
        threads_per_core=$((siblings / cpu_cores))
        echo -e "Threads per Core: ${YELLOW}$threads_per_core${NC}"
    fi
fi
echo ""

# 2. RAM SPECIFICATIONS
echo -e "${GREEN}${BOLD}[2] RAM SPECIFICATIONS${NC}"
echo -e "${LINE}"
if [ -f /proc/meminfo ]; then
    total_ram=$(grep MemTotal /proc/meminfo | awk '{printf "%.2f GB", $2/1024/1024}')
    free_ram=$(grep MemFree /proc/meminfo | awk '{printf "%.2f GB", $2/1024/1024}')
    available_ram=$(grep MemAvailable /proc/meminfo | awk '{printf "%.2f GB", $2/1024/1024}')
    
    echo -e "Total RAM: ${YELLOW}$total_ram${NC}"
    echo -e "Free RAM: ${YELLOW}$free_ram${NC}"
    echo -e "Available RAM: ${YELLOW}$available_ram${NC}"
    
    if command -v dmidecode &> /dev/null && [ $(id -u) -eq 0 ]; then
        ram_type=$(dmidecode -t memory 2>/dev/null | grep 'Type:' | head -1 | cut -d: -f2 | xargs)
        ram_speed=$(dmidecode -t memory 2>/dev/null | grep 'Speed:' | head -1 | cut -d: -f2 | xargs)
        [ -n "$ram_type" ] && echo -e "Type: ${YELLOW}$ram_type${NC}"
        [ -n "$ram_speed" ] && echo -e "Speed: ${YELLOW}$ram_speed${NC}"
    fi
fi
echo ""

# 3. DISK SPECIFICATIONS
echo -e "${GREEN}${BOLD}[3] DISK SPECIFICATIONS${NC}"
echo -e "${LINE}"
if command -v lsblk &> /dev/null; then
    echo -e "${YELLOW}Disk Devices:${NC}"
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep disk | while read line; do
        echo -e "  $line"
    done
fi

# Use universal df command
echo -e "\n${YELLOW}Mount Points Usage:${NC}"
show_disk_usage | while read line; do
    echo -e "  $line"
done
echo ""

# 4. MOTHERBOARD SPECIFICATIONS
echo -e "${GREEN}${BOLD}[4] MOTHERBOARD SPECIFICATIONS${NC}"
echo -e "${LINE}"
if command -v dmidecode &> /dev/null && [ $(id -u) -eq 0 ]; then
    mb_manufacturer=$(dmidecode -t baseboard 2>/dev/null | grep 'Manufacturer' | cut -d: -f2 | xargs)
    mb_product=$(dmidecode -t baseboard 2>/dev/null | grep 'Product Name' | cut -d: -f2 | xargs)
    mb_serial=$(dmidecode -t baseboard 2>/dev/null | grep 'Serial Number' | cut -d: -f2 | xargs)
    
    echo -e "Manufacturer: ${YELLOW}${mb_manufacturer:-Not Available}${NC}"
    echo -e "Product: ${YELLOW}${mb_product:-Not Available}${NC}"
    echo -e "Serial: ${YELLOW}${mb_serial:-Not Available}${NC}"
    
    bios_vendor=$(dmidecode -t bios 2>/dev/null | grep 'Vendor' | cut -d: -f2 | xargs)
    bios_version=$(dmidecode -t bios 2>/dev/null | grep 'Version' | cut -d: -f2 | xargs)
    echo -e "BIOS Vendor: ${YELLOW}${bios_vendor:-Not Available}${NC}"
    echo -e "BIOS Version: ${YELLOW}${bios_version:-Not Available}${NC}"
else
    echo -e "${YELLOW}Motherboard info requires root access (run with sudo)${NC}"
fi
echo ""

# 5. NETWORK CARD SPECIFICATIONS
echo -e "${GREEN}${BOLD}[5] NETWORK CARD SPECIFICATIONS${NC}"
echo -e "${LINE}"
echo -e "${YELLOW}Network Interfaces:${NC}"

# Get network interfaces
if [ -d /sys/class/net ]; then
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        mac=$(cat /sys/class/net/$iface/address 2>/dev/null)
        speed_file="/sys/class/net/$iface/speed"
        if [ -f "$speed_file" ]; then
            speed=$(cat "$speed_file" 2>/dev/null)
            [ "$speed" = "-1" ] || [ "$speed" = "65535" ] && speed="Unknown"
            [ "$speed" != "Unknown" ] && speed="${speed} Mbps"
        else
            speed="Unknown"
        fi
        state=$(cat /sys/class/net/$iface/operstate 2>/dev/null)
        
        echo -e "  ${GREEN}$iface:${NC}"
        [ -n "$mac" ] && echo -e "    MAC: ${YELLOW}$mac${NC}"
        echo -e "    Speed: ${YELLOW}${speed}${NC}"
        [ -n "$state" ] && echo -e "    State: ${YELLOW}$state${NC}"
    done
fi

# Show IP addresses
echo -e "\n${YELLOW}IP Addresses:${NC}"
if command -v ip &> /dev/null; then
    ip -o addr show | grep -v inet6 | grep -v '127.0.0.1' | while read line; do
        iface=$(echo $line | awk '{print $2}')
        ip=$(echo $line | awk '{print $4}' | cut -d/ -f1)
        echo -e "  ${GREEN}$iface:${NC} ${YELLOW}$ip${NC}"
    done
elif command -v ifconfig &> /dev/null; then
    ifconfig | grep -E 'inet ' | grep -v '127.0.0.1' | while read line; do
        echo -e "  ${YELLOW}$line${NC}"
    done
fi

echo -e "\n${BLUE}${BOLD}${LINE}${NC}"
echo -e "${BLUE}${BOLD}Report generated by Ultahost Server Scanner${NC}"
echo -e "${BLUE}${BOLD}${LINE}${NC}"
