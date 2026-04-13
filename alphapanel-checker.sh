#!/bin/bash

# ==============================================
# PanelAlpha Requirements Checker for cPanel
# ==============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Icons
CHECK_MARK="✓"
CROSS_MARK="✗"
WARNING="⚠"
INFO="ℹ"

# Divider line
divider() {
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Header
show_header() {
    clear
    echo ""
    printf "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAGENTA}║                      PanelAlpha Requirements Checker                          ║${NC}\n"
    printf "${BOLD}${MAGENTA}║                              for cPanel Server                                ║${NC}\n"
    printf "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""
}

# Get current PHP version from native PHP
get_php_version() {
    /usr/local/bin/php -v 2>/dev/null | head -n1 | awk '{print $2}' || echo "Unknown"
}

# Get PHP memory limit from native PHP
get_php_memory_limit() {
    /usr/local/bin/php -r "echo ini_get('memory_limit');" 2>/dev/null || echo "Unknown"
}

# Check if PHP extension is loaded in native PHP
check_native_extension() {
    /usr/local/bin/php -r "echo extension_loaded('$1') ? 'true' : 'false';" 2>/dev/null
}

# Check if ionCube Loader is loaded
check_ioncube() {
    /usr/local/bin/php -v 2>/dev/null | grep -q "ionCube" && echo "true" || echo "false"
}

# Get all available PHP versions on cPanel
get_cpanel_php_versions() {
    ls /opt/cpanel/ 2>/dev/null | grep -E "^ea-php[0-9]" | sed 's/ea-php//' | sort -V | tr '\n' ' ' || echo "None found"
}

# Print requirement status
print_status() {
    local name=$1
    local status=$2
    local value=$3
    
    printf "${CYAN}  %-30s${NC}" "$name"
    if [ "$status" == "true" ] || [ "$status" == "enabled" ]; then
        printf "${GREEN}${BOLD}[${CHECK_MARK} OK]${NC}    ${GREEN}%s${NC}\n" "$value"
    elif [ "$status" == "warning" ]; then
        printf "${YELLOW}${BOLD}[${WARNING} WARN]${NC}  ${YELLOW}%s${NC}\n" "$value"
    else
        printf "${RED}${BOLD}[${CROSS_MARK} FAIL]${NC}  ${RED}%s${NC}\n" "$value"
    fi
}

# Main execution
main() {
    show_header
    
    # Get PHP information
    PHP_VERSION=$(get_php_version)
    MEMORY_LIMIT=$(get_php_memory_limit)
    
    # Display PHP Info Section
    printf "${BOLD}${BLUE}${INFO} PHP Configuration (Native Server)${NC}\n"
    divider
    
    printf "${CYAN}  %-30s${NC}${BOLD}%s${NC}\n" "PHP Version:" "$PHP_VERSION"
    
    # Check if PHP version is supported
    PHP_MAJOR_MINOR=$(echo $PHP_VERSION | cut -d. -f1,2)
    case $PHP_MAJOR_MINOR in
        "7.4"|"8.0"|"8.4")
            printf "${CYAN}  %-30s${NC}${GREEN}${BOLD}[${CHECK_MARK} Supported]${NC}    ${GREEN}PHP %s is compatible${NC}\n" "Version Support:" "$PHP_MAJOR_MINOR"
            ;;
        *)
            printf "${CYAN}  %-30s${NC}${YELLOW}${BOLD}[${WARNING} Warning]${NC}  ${YELLOW}PHP %s may not be optimal${NC}\n" "Version Support:" "$PHP_MAJOR_MINOR"
            ;;
    esac
    
    # Memory limit check
    MEMORY_VALUE=$(echo $MEMORY_LIMIT | sed 's/[^0-9]//g')
    MEMORY_UNIT=$(echo $MEMORY_LIMIT | sed 's/[0-9]//g')
    
    if [ "$MEMORY_UNIT" == "M" ] && [ "$MEMORY_VALUE" -lt 128 ] 2>/dev/null; then
        printf "${CYAN}  %-30s${NC}${YELLOW}${BOLD}[${WARNING} Low]${NC}     ${YELLOW}%s (Recommend: 128M or higher)${NC}\n" "Memory Limit:" "$MEMORY_LIMIT"
    elif [ "$MEMORY_VALUE" == "-1" ] 2>/dev/null; then
        printf "${CYAN}  %-30s${NC}${GREEN}${BOLD}[${CHECK_MARK} OK]${NC}    ${GREEN}%s (Unlimited)${NC}\n" "Memory Limit:" "$MEMORY_LIMIT"
    else
        printf "${CYAN}  %-30s${NC}${GREEN}${BOLD}[${CHECK_MARK} OK]${NC}    ${GREEN}%s${NC}\n" "Memory Limit:" "$MEMORY_LIMIT"
    fi
    
    echo ""
    
    # Display available PHP versions in cPanel
    printf "${BOLD}${BLUE}${INFO} Available PHP Versions in cPanel${NC}\n"
    divider
    CPANEL_PHP_VERSIONS=$(get_cpanel_php_versions)
    printf "${CYAN}  Installed versions:${NC} ${GREEN}%s${NC}\n" "$CPANEL_PHP_VERSIONS"
    echo ""
    
    # Display PHP Extensions Status
    printf "${BOLD}${BLUE}${INFO} PHP Extensions Status (Native Server)${NC}\n"
    divider
    
    # ionCube Loader
    IONCUBE_STATUS=$(check_ioncube)
    if [ "$IONCUBE_STATUS" == "true" ]; then
        IONCUBE_VERSION=$(/usr/local/bin/php -v 2>/dev/null | grep -o "ionCube PHP Loader [^,]*" | head -n1 | sed 's/ionCube PHP Loader //')
        print_status "ionCube Loader" "true" "$IONCUBE_VERSION"
    else
        print_status "ionCube Loader" "false" "Not installed (Required)"
    fi
    
    # cURL
    CURL_STATUS=$(check_native_extension "curl")
    if [ "$CURL_STATUS" == "true" ]; then
        CURL_VERSION=$(/usr/local/bin/php -r "echo curl_version()['version'];")
        print_status "cURL" "true" "$CURL_VERSION"
    else
        print_status "cURL" "false" "Not installed (Required)"
    fi
    
    # mbstring
    MBSTRING_STATUS=$(check_native_extension "mbstring")
    if [ "$MBSTRING_STATUS" == "true" ]; then
        print_status "mbstring" "true" "Enabled"
    else
        print_status "mbstring" "false" "Not installed (Required)"
    fi
    
    # DOM
    DOM_STATUS=$(check_native_extension "dom")
    if [ "$DOM_STATUS" == "true" ]; then
        print_status "DOM" "true" "Enabled"
    else
        print_status "DOM" "false" "Not installed (Required)"
    fi
    
    # FileInfo
    FILEINFO_STATUS=$(check_native_extension "fileinfo")
    if [ "$FILEINFO_STATUS" == "true" ]; then
        print_status "FileInfo" "true" "Enabled"
    else
        print_status "FileInfo" "false" "Not installed (Required)"
    fi
    
    # Zip
    ZIP_STATUS=$(check_native_extension "zip")
    if [ "$ZIP_STATUS" == "true" ]; then
        print_status "Zip" "true" "Enabled"
    else
        print_status "Zip" "false" "Not installed (Required)"
    fi
    
    # Additional useful extensions
    echo ""
    printf "${BOLD}${BLUE}${INFO} Additional PHP Extensions Status${NC}\n"
    divider
    
    # MySQLi
    MYSQLI_STATUS=$(check_native_extension "mysqli")
    if [ "$MYSQLI_STATUS" == "true" ]; then
        print_status "MySQLi" "true" "Enabled"
    else
        print_status "MySQLi" "warning" "Not installed (Recommended)"
    fi
    
    # JSON
    JSON_STATUS=$(check_native_extension "json")
    if [ "$JSON_STATUS" == "true" ]; then
        print_status "JSON" "true" "Enabled"
    else
        print_status "JSON" "warning" "Not installed (Recommended)"
    fi
    
    # OpenSSL
    OPENSSL_STATUS=$(check_native_extension "openssl")
    if [ "$OPENSSL_STATUS" == "true" ]; then
        print_status "OpenSSL" "true" "Enabled"
    else
        print_status "OpenSSL" "warning" "Not installed (Recommended)"
    fi
    
    # GD
    GD_STATUS=$(check_native_extension "gd")
    if [ "$GD_STATUS" == "true" ]; then
        print_status "GD" "true" "Enabled"
    else
        print_status "GD" "warning" "Not installed (Recommended)"
    fi
    
    echo ""
    divider
    
    # Summary
    echo ""
    printf "${BOLD}${MAGENTA}Summary & Recommendations:${NC}\n"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    REQUIRED_MISSING=0
    
    if [ "$IONCUBE_STATUS" != "true" ]; then
        echo -e "${RED}${CROSS_MARK} ionCube Loader is REQUIRED but not installed.${NC}"
        echo -e "   ${CYAN}→ Install via cPanel: Software → PHP Extensions → ionCube Loader${NC}"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
    
    if [ "$CURL_STATUS" != "true" ]; then
        echo -e "${RED}${CROSS_MARK} cURL extension is REQUIRED but not installed.${NC}"
        echo -e "   ${CYAN}→ Install via cPanel: Software → PHP Extensions → curl${NC}"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
    
    if [ "$MBSTRING_STATUS" != "true" ]; then
        echo -e "${RED}${CROSS_MARK} mbstring extension is REQUIRED but not installed.${NC}"
        echo -e "   ${CYAN}→ Install via cPanel: Software → PHP Extensions → mbstring${NC}"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
    
    if [ "$DOM_STATUS" != "true" ]; then
        echo -e "${RED}${CROSS_MARK} DOM extension is REQUIRED but not installed.${NC}"
        echo -e "   ${CYAN}→ Install via cPanel: Software → PHP Extensions → dom${NC}"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
    
    if [ "$FILEINFO_STATUS" != "true" ]; then
        echo -e "${RED}${CROSS_MARK} FileInfo extension is REQUIRED but not installed.${NC}"
        echo -e "   ${CYAN}→ Install via cPanel: Software → PHP Extensions → fileinfo${NC}"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
    
    if [ "$ZIP_STATUS" != "true" ]; then
        echo -e "${RED}${CROSS_MARK} Zip extension is REQUIRED but not installed.${NC}"
        echo -e "   ${CYAN}→ Install via cPanel: Software → PHP Extensions → zip${NC}"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
    
    if [ $REQUIRED_MISSING -eq 0 ]; then
        echo -e "${GREEN}${CHECK_MARK} All required extensions are installed!${NC}"
        echo -e "${GREEN}${CHECK_MARK} Server is ready for PanelAlpha installation.${NC}"
    else
        echo ""
        echo -e "${YELLOW}${WARNING} Missing $REQUIRED_MISSING required extension(s). Please install them before proceeding.${NC}"
    fi
    
    echo ""
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "${BOLD}Check completed at:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

# Run the main function
main
