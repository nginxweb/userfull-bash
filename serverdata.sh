#!/bin/bash

# Colors for pretty output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color (reset color)

# Header
echo -e "${BLUE}-------------------------------------------------${NC}"
echo -e "${BLUE}   Checking Installed Control Panels and Servers  ${NC}"
echo -e "${BLUE}-------------------------------------------------${NC}"

# Checking for control panels
echo -e "${YELLOW}Checking for control panels...${NC}"

CONTROL_PANEL_INSTALLED=false

# aaPanel
if [ -d "/www/server/panel" ]; then
    echo -e "${GREEN}aaPanel is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# CyberPanel
if [ -d "/usr/local/CyberCP" ]; then
    echo -e "${GREEN}CyberPanel is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# HestiaCP
if [ -d "/usr/local/hestia" ]; then
    echo -e "${GREEN}HestiaCP is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# cPanel (corrected path)
if [ -d "/usr/local/cpanel" ]; then
    echo -e "${GREEN}cPanel is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# ISPManager
if [ -d "/usr/local/ispmanager" ]; then
    echo -e "${GREEN}ISPManager is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# Plesk
if [ -d "/opt/plesk" ]; then
    echo -e "${GREEN}Plesk is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# ISPConfig
if [ -d "/usr/local/ispconfig" ]; then
    echo -e "${GREEN}ISPConfig is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# DirectAdmin
if [ -d "/usr/local/directadmin" ]; then
    echo -e "${GREEN}DirectAdmin is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# Webmin
if [ -d "/usr/share/webmin" ]; then
    echo -e "${GREEN}Webmin is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# Virtualmin
if [ -d "/usr/share/webmin/virtualmin" ]; then
    echo -e "${GREEN}Virtualmin is installed.${NC}"
    CONTROL_PANEL_INSTALLED=true
fi

# If no control panels are installed
if [ "$CONTROL_PANEL_INSTALLED" = false ]; then
    echo -e "${RED}No control panels are installed on this server.${NC}"
fi

# Line break for better separation
echo -e "${BLUE}-------------------------------------------------${NC}"

# Checking for installed web servers
echo -e "${YELLOW}Checking for installed web servers...${NC}"

# Web servers check
WEB_SERVER_INSTALLED=false

# Apache
if systemctl is-active --quiet apache2 || systemctl is-active --quiet httpd; then
    echo -e "${GREEN}Apache is running.${NC}"
    WEB_SERVER_INSTALLED=true
fi

# Nginx
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}Nginx is running.${NC}"
    WEB_SERVER_INSTALLED=true
fi

# LiteSpeed (lsws)
if systemctl is-active --quiet lsws; then
    echo -e "${GREEN}LiteSpeed (lsws) is running.${NC}"
    WEB_SERVER_INSTALLED=true
fi

# If no supported web server is running
if [ "$WEB_SERVER_INSTALLED" = false ]; then
    echo -e "${RED}No supported web server is running.${NC}"
fi

# Line break for better separation
echo -e "${BLUE}-------------------------------------------------${NC}"

# Displaying additional server information
echo -e "${YELLOW}Fetching additional server information...${NC}"

# Hostname
hostname=$(hostname)
echo -e "${GREEN}Hostname: ${NC}$hostname"

# Operating System and Version (with detailed distribution info)
if [ -f /etc/os-release ]; then
    os_name=$(grep '^NAME=' /etc/os-release | cut -d '=' -f2 | tr -d '"')
    os_version=$(grep '^VERSION=' /etc/os-release | cut -d '=' -f2 | tr -d '"')
    echo -e "${GREEN}Operating System: ${NC}$os_name $os_version"
else
    os=$(uname -s -r)
    echo -e "${GREEN}Operating System: ${NC}$os"
fi

# Line break for better separation
echo -e "${BLUE}-------------------------------------------------${NC}"

# RAM (GB)
ram=$(free -g | awk '/^Mem:/ {print $2}')
echo -e "${GREEN}RAM (GB): ${NC}$ram GB"

# Disk Capacity (GB)
disk=$(df -h / | awk 'NR==2 {print $2}')
echo -e "${GREEN}Disk Capacity: ${NC}$disk"

# CPU Cores
cpu_cores=$(nproc)
echo -e "${GREEN}CPU Cores: ${NC}$cpu_cores"

# Virtualization Type
virtualization=$(systemd-detect-virt)
echo -e "${GREEN}Virtualization Type: ${NC}$virtualization"

# Public IPv4 Address
ip=$(curl -s http://ipecho.net/plain)
echo -e "${GREEN}Public IPv4 Address: ${NC}$ip"

# Line break for better separation
echo -e "${BLUE}-------------------------------------------------${NC}"

# Footer
echo -e "${BLUE}    Server check completed. See above for details. ${NC}"
echo -e "${BLUE}-------------------------------------------------${NC}"
