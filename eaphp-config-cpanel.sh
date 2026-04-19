#!/bin/bash

# Script: fix_php_settings.sh
# Purpose: Update main php.ini for all installed EA-PHP versions and force CageFS update

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Backup directory
BACKUP_DIR="/root/php_ini_backups_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo -e "${GREEN}[INFO] Starting PHP configuration update...${NC}"
echo -e "${GREEN}[INFO] Backup directory: $BACKUP_DIR${NC}"

# Find all EA-PHP installations
PHP_VERSIONS=$(find /opt/cpanel/ea-php* -maxdepth 0 -type d 2>/dev/null | grep -E 'ea-php[0-9]+' | sort -V)

if [[ -z "$PHP_VERSIONS" ]]; then
    echo -e "${RED}[ERROR] No EA-PHP versions found in /opt/cpanel/${NC}"
    exit 1
fi

# New settings
declare -A SETTINGS=(
    ["max_input_time"]="60"
    ["max_execution_time"]="60"
    ["memory_limit"]="1024M"
    ["post_max_size"]="256M"
    ["upload_max_filesize"]="256M"
    ["allow_url_fopen"]="On"
    ["max_input_vars"]="3000"
    ["expose_php"]="Off"
    ["display_errors"]="Off"
)

DISABLE_FUNCTIONS="exec,system,passthru,shell_exec,proc_close,proc_open,dl,popen,show_source,posix_kill,posix_mkfifo,posix_getpwuid,posix_setpgid,posix_setsid,posix_setuid,posix_setgid,posix_seteuid,posix_setegid,posix_uname"

# Function to update or add a PHP setting
update_php_ini() {
    local php_ini_file="$1"
    local setting_name="$2"
    local setting_value="$3"
    
    if grep -qE "^\s*${setting_name}\s*=" "$php_ini_file"; then
        # Update existing setting
        sed -i "s/^\s*${setting_name}\s*=.*/${setting_name} = ${setting_value}/" "$php_ini_file"
        echo -e "${GREEN}  ✓ Updated ${setting_name} = ${setting_value}${NC}"
    else
        # Add new setting at the end of file
        echo "${setting_name} = ${setting_value}" >> "$php_ini_file"
        echo -e "${GREEN}  ✓ Added ${setting_name} = ${setting_value}${NC}"
    fi
}

# Process each PHP version
for php_path in $PHP_VERSIONS; do
    php_version=$(basename "$php_path" | sed 's/ea-php//')
    php_ini_file="$php_path/root/etc/php.ini"
    
    echo -e "\n${YELLOW}Processing PHP version: $php_version${NC}"
    echo -e "Config file: $php_ini_file"
    
    if [[ ! -f "$php_ini_file" ]]; then
        echo -e "${RED}[WARNING] php.ini not found for PHP $php_version, skipping...${NC}"
        continue
    fi
    
    # Create backup
    backup_file="$BACKUP_DIR/php.ini_$php_version.backup"
    cp "$php_ini_file" "$backup_file"
    echo -e "${GREEN}[INFO] Backup saved to: $backup_file${NC}"
    
    # Update each setting
    for setting in "${!SETTINGS[@]}"; do
        update_php_ini "$php_ini_file" "$setting" "${SETTINGS[$setting]}"
    done
    
    # Handle disable_functions
    if grep -qE "^\s*disable_functions\s*=" "$php_ini_file"; then
        sed -i "s/^\s*disable_functions\s*=.*/disable_functions = ${DISABLE_FUNCTIONS}/" "$php_ini_file"
        echo -e "${GREEN}  ✓ Updated disable_functions${NC}"
    else
        echo "disable_functions = ${DISABLE_FUNCTIONS}" >> "$php_ini_file"
        echo -e "${GREEN}  ✓ Added disable_functions${NC}"
    fi
    
    echo -e "${GREEN}[INFO] PHP $php_version configuration completed.${NC}"
done

# Update CLI PHP for each version separately
echo -e "\n${YELLOW}[INFO] Updating CLI PHP configurations...${NC}"
for php_path in $PHP_VERSIONS; do
    php_version=$(basename "$php_path" | sed 's/ea-php//')
    cli_ini_file="$php_path/root/etc/php.ini"
    
    # This is the same file, but we ensure it's updated
    if [[ -f "$cli_ini_file" ]]; then
        echo -e "${GREEN}  ✓ CLI PHP $php_version uses: $cli_ini_file${NC}"
    fi
done

# Also update the system default PHP CLI (if different from EA versions)
echo -e "\n${YELLOW}[INFO] Checking system default PHP CLI...${NC}"
default_php=$(which php)
if [[ -n "$default_php" && -f "$default_php" ]]; then
    default_ini=$($default_php -i 2>/dev/null | grep "Loaded Configuration File" | awk '{print $4}')
    if [[ -n "$default_ini" && -f "$default_ini" ]]; then
        echo -e "${YELLOW}Default PHP CLI uses: $default_ini${NC}"
        
        # Check if it's already updated (if it points to an EA version)
        if [[ ! "$default_ini" =~ /opt/cpanel/ea-php ]]; then
            backup_file="$BACKUP_DIR/php_cli_default.backup"
            cp "$default_ini" "$backup_file"
            echo -e "${GREEN}[INFO] Backup saved to: $backup_file${NC}"
            
            for setting in "${!SETTINGS[@]}"; do
                update_php_ini "$default_ini" "$setting" "${SETTINGS[$setting]}"
            done
            
            if grep -qE "^\s*disable_functions\s*=" "$default_ini"; then
                sed -i "s/^\s*disable_functions\s*=.*/disable_functions = ${DISABLE_FUNCTIONS}/" "$default_ini"
            else
                echo "disable_functions = ${DISABLE_FUNCTIONS}" >> "$default_ini"
            fi
        fi
    fi
fi

# Restart PHP-FPM for all versions
echo -e "\n${YELLOW}[INFO] Restarting PHP-FPM services...${NC}"
for php_path in $PHP_VERSIONS; do
    php_version=$(basename "$php_path" | sed 's/ea-php//')
    if systemctl list-units --full -all | grep -Fq "ea-php${php_version}-php-fpm.service"; then
        systemctl restart "ea-php${php_version}-php-fpm"
        echo -e "${GREEN}  ✓ Restarted ea-php${php_version}-php-fpm${NC}"
    fi
done

# Force CageFS update for all users
echo -e "\n${YELLOW}[INFO] Forcing CageFS update for all users...${NC}"
if command -v cagefsctl &> /dev/null; then
    cagefsctl --force-update
    echo -e "${GREEN}✓ CageFS update completed.${NC}"
else
    echo -e "${RED}[WARNING] cagefsctl not found. Is CloudLinux installed?${NC}"
fi

# Verification for all PHP versions
echo -e "\n${GREEN}[INFO] Script completed!${NC}"
echo -e "${YELLOW}To verify settings for each PHP version, run:${NC}"

for php_path in $PHP_VERSIONS; do
    php_version=$(basename "$php_path" | sed 's/ea-php//')
    php_bin="$php_path/root/usr/bin/php"
    if [[ -f "$php_bin" ]]; then
        echo -e "\n${YELLOW}=== PHP $php_version ===${NC}"
        echo "  $php_bin -i | grep -E '(max_execution_time|max_input_time|memory_limit|post_max_size|upload_max_filesize)'"
    fi
done

# Verify current CLI
echo -e "\n${YELLOW}=== Current CLI PHP (php -i) ===${NC}"
echo "  php -i | grep -E '(max_execution_time|max_input_time|memory_limit|post_max_size|upload_max_filesize)'"
