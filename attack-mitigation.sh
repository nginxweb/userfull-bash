#!/bin/bash

# DDoS Mitigation Script - Add iptables rules based on domain name
# Usage: ./ddos_mitigation.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${NC}"
        exit 1
    fi
}

# Function to validate domain format
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9]$ ]]; then
        echo -e "${RED}Invalid domain format!${NC}"
        return 1
    fi
    return 0
}

# Function to add iptables rules
add_iptables_rules() {
    local domain=$1
    local rules_added=0
    
    echo -e "${GREEN}Adding iptables rules for domain: $domain${NC}"
    
    # Rule 1: Port 80 - string match
    if iptables -I INPUT 1 -p tcp --dport 80 -m string --string "$domain" --algo bm -j DROP 2>/dev/null; then
        echo -e "${GREEN}[+] Rule 1 added: DROP port 80 with string '$domain'${NC}"
        ((rules_added++))
    else
        echo -e "${RED}[-] Failed to add rule 1${NC}"
    fi
    
    # Rule 2: Port 443 - string match
    if iptables -I INPUT 1 -p tcp --dport 443 -m string --string "$domain" --algo bm -j DROP 2>/dev/null; then
        echo -e "${GREEN}[+] Rule 2 added: DROP port 443 with string '$domain'${NC}"
        ((rules_added++))
    else
        echo -e "${RED}[-] Failed to add rule 2${NC}"
    fi
    
    # Rule 3: Port 80 - Host header match
    if iptables -I INPUT 1 -p tcp --dport 80 -m string --string "Host: $domain" --algo bm -j DROP 2>/dev/null; then
        echo -e "${GREEN}[+] Rule 3 added: DROP port 80 with 'Host: $domain'${NC}"
        ((rules_added++))
    else
        echo -e "${RED}[-] Failed to add rule 3${NC}"
    fi
    
    # Rule 4: Port 443 - Host header match
    if iptables -I INPUT 1 -p tcp --dport 443 -m string --string "Host: $domain" --algo bm -j DROP 2>/dev/null; then
        echo -e "${GREEN}[+] Rule 4 added: DROP port 443 with 'Host: $domain'${NC}"
        ((rules_added++))
    else
        echo -e "${RED}[-] Failed to add rule 4${NC}"
    fi
    
    echo -e "${GREEN}Total rules added: $rules_added/4${NC}"
}

# Function to verify rules
verify_rules() {
    local domain=$1
    
    echo -e "\n${YELLOW}Verifying iptables rules for domain: $domain${NC}"
    echo -e "${YELLOW}========================================${NC}"
    
    iptables -L -n -v | grep -E "$domain|Chain INPUT" | head -20
    
    if iptables -L -n -v | grep -q "$domain"; then
        echo -e "\n${GREEN}[✓] Rules are active and working${NC}"
    else
        echo -e "\n${RED}[✗] No rules found for domain: $domain${NC}"
    fi
}

# Function to get top 20 IPs from domlogs
get_top_ips() {
    local domain=$1
    local log_file="/usr/local/apache/domlogs/${domain}-ssl_log"
    
    if [[ ! -f "$log_file" ]]; then
        echo -e "${RED}Log file not found: $log_file${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}Top 20 IPs with highest traffic for: $domain${NC}"
    echo -e "${YELLOW}============================================${NC}"
    
    awk '{print $1}' "$log_file" | sort | uniq -c | sort -rn | head -20 | while read count ip; do
        printf "${GREEN}%10s${NC} %s\n" "$count" "$ip"
    done
    
    # Store top IPs in array for later use
    mapfile -t top_ips < <(awk '{print $1}' "$log_file" | sort | uniq -c | sort -rn | head -20 | awk '{print $2}')
    return 0
}

# Function to block IPs with imunify360
block_ips() {
    local domain=$1
    local threshold=300
    
    echo -e "\n${YELLOW}Scanning for IPs with more than $threshold requests...${NC}"
    
    local ips_to_block=()
    while read -r count ip; do
        if [[ $count -gt $threshold ]]; then
            ips_to_block+=("$ip")
            echo -e "${RED}IP: $ip - $count requests (exceeds threshold)${NC}"
        fi
    done < <(awk '{count[$1]++} END {for (ip in count) print count[ip], ip}' "/usr/local/apache/domlogs/${domain}-ssl_log" 2>/dev/null | sort -rn)
    
    if [[ ${#ips_to_block[@]} -eq 0 ]]; then
        echo -e "${GREEN}No IPs exceed the threshold of $threshold requests.${NC}"
        return 0
    fi
    
    echo -e "\n${YELLOW}Found ${#ips_to_block[@]} IP(s) exceeding threshold.${NC}"
    read -p "Do you want to block these IPs using imunify360? (yes/no): " confirm
    
    if [[ "$confirm" =~ ^(yes|y|Y|YES)$ ]]; then
        echo -e "${GREEN}Blocking IPs...${NC}"
        for ip in "${ips_to_block[@]}"; do
            if imunify360-agent ip-list local add --purpose drop "$ip" --comment "DDoS Attack on ${domain} - High Requests" 2>/dev/null; then
                echo -e "${GREEN}[+] Blocked: $ip${NC}"
            else
                echo -e "${RED}[-] Failed to block: $ip${NC}"
            fi
        done
        echo -e "${GREEN}Blocking process completed.${NC}"
    else
        echo -e "${YELLOW}No IPs were blocked.${NC}"
    fi
}

# Function to save iptables rules persistently
save_rules() {
    echo -e "\n${YELLOW}Do you want to save iptables rules persistently? (yes/no): ${NC}"
    read -r save_confirm
    
    if [[ "$save_confirm" =~ ^(yes|y|Y|YES)$ ]]; then
        if command -v iptables-save >/dev/null 2>&1; then
            if [[ -f /etc/redhat-release ]]; then
                service iptables save 2>/dev/null || iptables-save > /etc/sysconfig/iptables
            else
                iptables-save > /etc/iptables/rules.v4 2>/dev/null || netfilter-persistent save 2>/dev/null
            fi
            echo -e "${GREEN}Rules saved successfully!${NC}"
        else
            echo -e "${RED}iptables-save not found. Rules saved only for current session.${NC}"
        fi
    fi
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -d, --domain DOMAIN    Specify domain name directly"
    echo "  -h, --help            Show this help message"
    echo "  -s, --skip-block      Skip IP blocking prompt"
    echo ""
    echo "Example: $0 -d example.com"
}

# Main script execution
main() {
    check_root
    
    local domain=""
    local skip_block=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                domain="$2"
                shift 2
                ;;
            -s|--skip-block)
                skip_block=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Get domain from user if not provided
    if [[ -z "$domain" ]]; then
        read -p "Enter domain name (e.g., example.com): " domain
    fi
    
    # Validate domain
    if ! validate_domain "$domain"; then
        exit 1
    fi
    
    # Show summary
    clear
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}   DDoS Mitigation Script${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "Target Domain: ${YELLOW}$domain${NC}"
    echo -e "Start Time: ${YELLOW}$(date)${NC}"
    echo -e "${GREEN}================================${NC}\n"
    
    # Add iptables rules
    add_iptables_rules "$domain"
    
    # Verify rules
    verify_rules "$domain"
    
    # Get top 20 IPs
    get_top_ips "$domain"
    
    # Block IPs if not skipped
    if [[ "$skip_block" == false ]]; then
        block_ips "$domain"
    else
        echo -e "${YELLOW}Skipping IP blocking as requested.${NC}"
    fi
    
    # Save rules
    save_rules
    
    echo -e "\n${GREEN}================================${NC}"
    echo -e "${GREEN}Script execution completed!${NC}"
    echo -e "${GREEN}================================${NC}"
    
    # Show final iptables rules count
    echo -e "\n${YELLOW}Current iptables rules count:${NC}"
    iptables -L INPUT -n --line-numbers | head -10
}

# Run main function with all arguments
main "$@"
