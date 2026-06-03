#!/bin/bash

# Script: check_deleted_user_backup.sh
# Purpose: Check deleted cPanel user backup status in JetBackup5
# Usage: ./check_deleted_user_backup.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Clear screen for better readability
clear

# Display banner
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Deleted cPanel User Backup Investigation Tool       ║${NC}"
echo -e "${CYAN}║                    JetBackup5 Analyzer                   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Ask for username
echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│${NC}  Enter the cPanel username to investigate: ${YELLOW}\c${NC}"
read USERNAME
echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
echo ""

# Validate input
if [ -z "$USERNAME" ]; then
    echo -e "${RED}✗ Error: Username cannot be empty!${NC}"
    exit 1
fi

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Checking deleted user: ${YELLOW}$USERNAME${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Function to check cPanel removal date
check_cpanel_removal() {
    echo -e "${BLUE}[1] Checking cPanel account removal date...${NC}"
    
    REMOVE_DATE=$(grep "$USERNAME" /var/cpanel/accounting.log 2>/dev/null | grep -i "REMOVE" | head -1 | awk '{print $1, $2, $3, $4}')
    
    if [ -n "$REMOVE_DATE" ]; then
        echo -e "${GREEN}✓ Account removed from cPanel on: ${YELLOW}$REMOVE_DATE${NC}"
        
        # Calculate days since removal
        REMOVE_EPOCH=$(date -d "$(echo $REMOVE_DATE | awk '{print $1, $2, $3}')" +%s 2>/dev/null)
        CURRENT_EPOCH=$(date +%s)
        if [ -n "$REMOVE_EPOCH" ]; then
            DAYS_DIFF=$(( (CURRENT_EPOCH - REMOVE_EPOCH) / 86400 ))
            echo -e "${GREEN}  → Removed ${YELLOW}$DAYS_DIFF${GREEN} days ago${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ No REMOVE record found in accounting.log${NC}"
        echo -e "  (Account may still exist or was removed differently)"
    fi
    echo ""
}

# Function to check last successful backup (Transferring account)
check_last_successful_backup() {
    echo -e "${BLUE}[2] Checking last successful backups (Transferring account to PBS)...${NC}"
    
    # Get all successful backup dates
    BACKUP_DATES=$(grep -h "Transferring account.*$USERNAME" /usr/local/jetapps/var/log/jetbackup5/queue/*.log 2>/dev/null | grep -oP '\[\K[0-9]{2}/[A-Za-z]{3}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}' | sort -r | uniq)
    
    if [ -n "$BACKUP_DATES" ]; then
        echo -e "${GREEN}✓ Successful backups found:${NC}"
        echo "$BACKUP_DATES" | while read line; do
            echo -e "    ${YELLOW}📁 $line${NC}"
        done
        
        # Show count and latest
        COUNT=$(echo "$BACKUP_DATES" | wc -l)
        LATEST=$(echo "$BACKUP_DATES" | head -1)
        echo -e "${GREEN}  → Total backups: ${YELLOW}$COUNT${NC}"
        echo -e "${GREEN}  → Latest backup: ${YELLOW}$LATEST${NC}"
    else
        echo -e "${RED}✗ No successful backup found for this user${NC}"
    fi
    echo ""
}

# Function to check orphan cleanup
check_orphan_cleanup() {
    echo -e "${BLUE}[3] Checking orphan cleanup status...${NC}"
    
    # Check if user was deleted as orphan
    ORPHAN_DELETE=$(grep -r "$USERNAME" /usr/local/jetapps/var/log/jetbackup5/ --include="*.log" 2>/dev/null | \
                    grep -i "Deleting orphan account")
    
    if [ -n "$ORPHAN_DELETE" ]; then
        DELETE_DATE=$(echo "$ORPHAN_DELETE" | grep -oP '\[\K[^\]]+' | head -1)
        echo -e "${RED}✓ Backup was deleted as orphan on: ${YELLOW}$DELETE_DATE${NC}"
        echo -e "  Reason: Account no longer exists in cPanel but had records in JetBackup"
    else
        echo -e "${GREEN}✓ No orphan cleanup record found (backup may still exist in PBS)${NC}"
    fi
    
    # Check for snapshot deletions
    SNAPSHOT_DELETE=$(grep -r "$USERNAME" /usr/local/jetapps/var/log/jetbackup5/ --include="*.log" 2>/dev/null | \
                      grep "Deleting snapshot" | head -3)
    
    if [ -n "$SNAPSHOT_DELETE" ]; then
        echo -e "${YELLOW}  → Recent snapshot deletions:${NC}"
        echo "$SNAPSHOT_DELETE" | while read line; do
            SNAP_DATE=$(echo "$line" | grep -oP '\[\K[^\]]+' | head -1)
            echo -e "    - $SNAP_DATE"
        done
    fi
    echo ""
}

# Function to check PBS destination status
check_pbs_destination() {
    echo -e "${BLUE}[4] Checking PBS (Proxmox Backup Server) destination...${NC}"
    
    # Check JetBackup5 PBS configuration
    if [ -f "/usr/local/jetapps/var/jetbackup5/destinations.yaml" ]; then
        PBS_CONFIG=$(grep -A5 "pbs" /usr/local/jetapps/var/jetbackup5/destinations.yaml 2>/dev/null | head -10)
        if [ -n "$PBS_CONFIG" ]; then
            echo -e "${GREEN}✓ PBS destination is configured in JetBackup5${NC}"
        fi
    fi
    
    # Check for any PBS-related logs for this user
    PBS_LOGS=$(grep -r "$USERNAME" /usr/local/jetapps/var/log/jetbackup5/ --include="*.log" 2>/dev/null | \
               grep -i "pbs" | tail -3)
    
    if [ -n "$PBS_LOGS" ]; then
        echo -e "${GREEN}  PBS interactions found:${NC}"
        echo "$PBS_LOGS" | while read line; do
            PBS_DATE=$(echo "$line" | grep -oP '\[\K[^\]]+' | head -1)
            echo -e "    - $PBS_DATE"
        done
    else
        echo -e "${YELLOW}  No recent PBS logs found for this user${NC}"
    fi
    echo ""
}

# Function to check integrity checks (backup attempts)
check_integrity_checks() {
    echo -e "${BLUE}[5] Checking recent integrity checks (backup verification)...${NC}"
    
    INTEGRITY_CHECKS=$(grep -r "$USERNAME" /usr/local/jetapps/var/log/jetbackup5/ --include="*.log" 2>/dev/null | \
                       grep "Integrity check" | grep -oP '\[\K[0-9]{2}/[A-Za-z]{3}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}' | sort -r | uniq | head -10)
    
    if [ -n "$INTEGRITY_CHECKS" ]; then
        echo -e "${YELLOW}  Last 10 integrity checks:${NC}"
        echo "$INTEGRITY_CHECKS" | while read line; do
            echo -e "    - $line"
        done
    else
        echo -e "  No integrity check records found"
    fi
    echo ""
}

# Function to check if user exists in cPanel now
check_current_cpanel_status() {
    echo -e "${BLUE}[6] Checking current cPanel status...${NC}"
    
    if [ -d "/var/cpanel/users/$USERNAME" ] || grep -q "^$USERNAME:" /etc/domainusers 2>/dev/null; then
        echo -e "${GREEN}✓ User EXISTS in cPanel${NC}"
    else
        echo -e "${RED}✗ User does NOT exist in cPanel (has been terminated)${NC}"
    fi
    echo ""
}

# Function to show summary timeline
show_timeline() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}SUMMARY TIMELINE${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    # Extract dates from previous checks
    REMOVE_DATE_RAW=$(grep "$USERNAME" /var/cpanel/accounting.log 2>/dev/null | grep -i "REMOVE" | head -1 | awk '{print $1, $2, $3}')
    LATEST_BACKUP=$(grep -h "Transferring account.*$USERNAME" /usr/local/jetapps/var/log/jetbackup5/queue/*.log 2>/dev/null | grep -oP '\[\K[0-9]{2}/[A-Za-z]{3}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}' | sort -r | uniq | head -1)
    ORPHAN_DELETE_RAW=$(grep -r "$USERNAME" /usr/local/jetapps/var/log/jetbackup5/ --include="*.log" 2>/dev/null | \
                        grep -i "Deleting orphan account" | grep -oP '\[\K[^\]]+' | head -1)
    
    if [ -n "$LATEST_BACKUP" ]; then
        echo -e "${GREEN}Last successful backup:${NC}     $LATEST_BACKUP"
    else
        echo -e "${GREEN}Last successful backup:${NC}     ${RED}NOT FOUND${NC}"
    fi
    
    if [ -n "$REMOVE_DATE_RAW" ]; then
        echo -e "${RED}Account termination:${NC}          $REMOVE_DATE_RAW"
    else
        echo -e "${RED}Account termination:${NC}          ${YELLOW}NOT FOUND IN LOGS (user may still exist)${NC}"
    fi
    
    if [ -n "$ORPHAN_DELETE_RAW" ]; then
        echo -e "${RED}Backup orphan deletion:${NC}       $ORPHAN_DELETE_RAW"
    else
        echo -e "${RED}Backup orphan deletion:${NC}       ${GREEN}NOT DELETED (may still exist in PBS)${NC}"
    fi
    
    echo -e "${CYAN}----------------------------------------${NC}"
    
    # Calculate and show reason
    if [ -n "$REMOVE_DATE_RAW" ] && [ -n "$ORPHAN_DELETE_RAW" ]; then
        echo -e "${YELLOW}ROOT CAUSE:${NC}"
        echo -e "  User was terminated from cPanel on $REMOVE_DATE_RAW"
        echo -e "  JetBackup5 automatically deleted the backup as an 'orphan account'"
        echo -e "  during scheduled cleanup on $ORPHAN_DELETE_RAW"
    elif [ -n "$REMOVE_DATE_RAW" ] && [ -z "$ORPHAN_DELETE_RAW" ]; then
        echo -e "${YELLOW}STATUS:${NC}"
        echo -e "  User terminated on $REMOVE_DATE_RAW but backup was NOT deleted as orphan"
        echo -e "  Backup may still exist in PBS destination"
    else
        echo -e "${YELLOW}STATUS:${NC}"
        echo -e "  No termination record found - user may still exist or was removed differently"
    fi
    echo ""
}

# Function to provide recovery suggestions
recovery_suggestions() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}RECOVERY SUGGESTIONS${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    echo -e "${BLUE}If backup was deleted as orphan:${NC}"
    echo -e "  1. Check PBS destination directly for any remaining snapshots:"
    echo -e "     ${YELLOW}proxmox-backup-client snapshots --repository <your-pbs-repo> | grep $USERNAME${NC}"
    echo -e "  2. Check JetBackup5 PBS destination configuration:"
    echo -e "     ${YELLOW}cat /usr/local/jetapps/var/jetbackup5/destinations.yaml${NC}"
    echo -e "  3. Contact customer for local backup copy"
    echo ""
    echo -e "${BLUE}To prevent future issues:${NC}"
    echo -e "  - Before terminating account, take manual backup:"
    echo -e "    ${YELLOW}/usr/bin/jetbackup5 --pkgacct $USERNAME${NC}"
    echo -e "  - Increase orphan retention period in JetBackup5 settings"
    echo -e "  - Implement pre-termination backup checklist"
    echo ""
    echo -e "${BLUE}To check PBS backup manually:${NC}"
    echo -e "  ${YELLOW}grep -r \"Transferring account.*$USERNAME\" /usr/local/jetapps/var/log/jetbackup5/ | grep -oP '\\[\\K[^\\]]+' | sort -r${NC}"
}

# Main execution
check_cpanel_removal
check_last_successful_backup
check_orphan_cleanup
check_pbs_destination
check_integrity_checks
check_current_cpanel_status
show_timeline
recovery_suggestions

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Script completed.${NC}"
