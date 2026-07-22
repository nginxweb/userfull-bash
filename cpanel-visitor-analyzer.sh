#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# cPanel domlogs path
DOMLOG_PATH="/usr/local/apache/domlogs"

# Get today's date in log format (e.g., 22/Jul/2026)
TODAY=$(date +"%d/%b/%Y")

# Function to display header
print_header() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${WHITE}              📊 cPanel Domain Log Analyzer                   ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Function to find all log files for a domain (recursive) - EXCLUDING bytes_log
find_domain_logs() {
    local domain=$1
    local log_files=()
    
    # Method 1: Direct match in domlogs directory (exclude bytes_log)
    for file in "$DOMLOG_PATH"/${domain}*; do
        if [ -f "$file" ] && [ -s "$file" ]; then
            filename=$(basename "$file")
            # Skip bytes_log files
            if [[ ! "$filename" == *"-bytes_log" ]]; then
                log_files+=("$file")
            fi
        fi
    done
    
    # Method 2: Search in subdirectories (exclude bytes_log)
    while IFS= read -r file; do
        if [ -f "$file" ] && [ -s "$file" ]; then
            filename=$(basename "$file")
            # Skip bytes_log files
            if [[ ! "$filename" == *"-bytes_log" ]]; then
                if [[ "$filename" == *"$domain"* ]] || [[ "$filename" == *"${domain%%.*}"* ]]; then
                    log_files+=("$file")
                fi
            fi
        fi
    done < <(find "$DOMLOG_PATH" -mindepth 2 -type f -name "*${domain}*" 2>/dev/null)
    
    # Method 3: Search for domain in any file (content search) - exclude bytes_log
    if [ ${#log_files[@]} -eq 0 ]; then
        while IFS= read -r file; do
            if [ -f "$file" ] && [ -s "$file" ]; then
                filename=$(basename "$file")
                if [[ ! "$filename" == *"-bytes_log" ]]; then
                    if grep -q "$domain" "$file" 2>/dev/null; then
                        log_files+=("$file")
                    fi
                fi
            fi
        done < <(find "$DOMLOG_PATH" -type f -size +1k 2>/dev/null | head -100)
    fi
    
    echo "${log_files[@]}"
}

# Function to count today's requests
count_today_requests() {
    local log_file=$1
    
    # Count lines containing today's date
    local today_count=$(grep -c "\[$TODAY" "$log_file" 2>/dev/null)
    
    if [ -z "$today_count" ]; then
        today_count=0
    fi
    
    echo "$today_count"
}

# Function for live monitoring
live_monitor() {
    local domain=$1
    local log_files=()
    
    # Find all log files
    log_files_output=$(find_domain_logs "$domain")
    IFS=' ' read -ra log_files <<< "$log_files_output"
    
    if [ ${#log_files[@]} -eq 0 ]; then
        echo -e "${RED}❌ No log files found for domain: $domain${NC}"
        exit 1
    fi
    
    # Clear screen and show header
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${WHITE}         🔴 LIVE MONITORING - ${CYAN}$domain${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}📡 Monitoring ${#log_files[@]} log file(s) in real-time...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    # Create array of log files for tail
    local tail_files=()
    for log_file in "${log_files[@]}"; do
        tail_files+=("-f" "$log_file")
    done
    
    # Tail all log files and format output
    tail "${tail_files[@]}" 2>/dev/null | while read line; do
        # Extract IP and URL from log line
        # Format: IP - - [date] "METHOD URL" status size
        local ip=$(echo "$line" | awk '{print $1}')
        local url=$(echo "$line" | awk '{print $7}')
        local method=$(echo "$line" | awk '{print $6}' | sed 's/"//g')
        local status=$(echo "$line" | awk '{print $9}')
        local time=$(echo "$line" | awk -F'[][]' '{print $2}')
        
        # Skip empty lines
        if [ -z "$ip" ] || [ -z "$url" ]; then
            continue
        fi
        
        # Color based on status code
        if [[ $status -ge 200 && $status -lt 300 ]]; then
            status_color=$GREEN
        elif [[ $status -ge 300 && $status -lt 400 ]]; then
            status_color=$BLUE
        elif [[ $status -ge 400 && $status -lt 500 ]]; then
            status_color=$YELLOW
        elif [[ $status -ge 500 ]]; then
            status_color=$RED
        else
            status_color=$WHITE
        fi
        
        # Color based on IP (highlight suspicious IPs)
        ip_color=$WHITE
        if [[ $ip == "79.133.41.250" ]] || [[ $ip == "38.108.182.11" ]]; then
            ip_color=$RED
        fi
        
        # Show formatted output
        printf "${DIM}%s${NC} ${ip_color}%-16s${NC} ${CYAN}%-8s${NC} ${status_color}%s${NC} ${WHITE}%s${NC}\n" \
            "$time" "$ip" "$method" "$status" "$url"
    done
}

# Function to analyze combined logs
analyze_combined_logs() {
    local domain=$1
    shift
    local log_files=("$@")
    
    # Create temporary combined file
    local temp_file="/tmp/combined_$$_${domain}_${RANDOM}.tmp"
    
    # Combine all log files
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ] && [ -s "$log_file" ]; then
            cat "$log_file" >> "$temp_file"
        fi
    done
    
    # Check if combined file has data
    if [ ! -s "$temp_file" ]; then
        echo -e "${RED}❌ No data found in log files${NC}"
        rm -f "$temp_file"
        return
    fi
    
    # Get stats
    local total_lines=$(wc -l < "$temp_file" 2>/dev/null | tr -d ' ')
    local today_requests=$(grep -c "\[$TODAY" "$temp_file" 2>/dev/null)
    local file_size=$(du -h "$temp_file" 2>/dev/null | cut -f1)
    
    # Show summary header
    echo -e "${BOLD}${GREEN}📊 Combined Report for: ${CYAN}$domain${NC}"
    echo -e "   ${DIM}📅 Today: $TODAY${NC}"
    echo -e "   ${DIM}📊 Total Requests (all logs): $total_lines${NC}"
    echo -e "   ${GREEN}📅 Today's Requests: $today_requests${NC}"
    echo -e "   ${DIM}📁 Log files combined: ${#log_files[@]}${NC}"
    echo ""
    
    # Show list of combined log files
    echo -e "${BOLD}${BLUE}📂 Combined Log Files:${NC}"
    for log_file in "${log_files[@]}"; do
        local filename=$(basename "$log_file")
        local filepath=$(dirname "$log_file")
        local lines=$(wc -l < "$log_file" 2>/dev/null | tr -d ' ')
        local size=$(du -h "$log_file" 2>/dev/null | cut -f1)
        local today_count=$(count_today_requests "$log_file")
        
        # Show full path
        if [ "$filepath" != "$DOMLOG_PATH" ]; then
            local subdir=$(basename "$filepath")
            printf "  ${WHITE}•${NC} ${CYAN}%s/${filename}${NC}\n" "$subdir"
        else
            printf "  ${WHITE}•${NC} ${CYAN}%s${NC}\n" "$filename"
        fi
        printf "    ${DIM}Lines: $lines | Today: ${GREEN}$today_count${NC} | Size: $size${NC}\n"
    done
    echo ""
    
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    # 1. Top IP Addresses
    echo -e "${YELLOW}🌐 Top IP Addresses:${NC}"
    awk '{print $1}' "$temp_file" 2>/dev/null | \
        sort | uniq -c | sort -rn | head -15 | \
        while read count ip; do
            if [ "$count" -gt 100 ]; then
                color=$RED
            elif [ "$count" -gt 50 ]; then
                color=$YELLOW
            else
                color=$GREEN
            fi
            printf "  ${WHITE}%-6s ${color}%-16s${NC}\n" "$count" "$ip"
        done
    echo ""
    
    # 2. Top URLs - SHOW TOP 20 ONLY
    echo -e "${YELLOW}📂 Top 20 URLs (by request count):${NC}"
    
    local url_list=$(awk '{print $7}' "$temp_file" 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -20)
    
    if [ -z "$url_list" ]; then
        echo -e "  ${DIM}No URLs found${NC}"
    else
        echo "$url_list" | while read count url; do
            if [ -z "$count" ] || [ -z "$url" ]; then
                continue
            fi
            if [ "$count" -gt 500 ]; then
                color=$RED
            elif [ "$count" -gt 200 ]; then
                color=$YELLOW
            else
                color=$CYAN
            fi
            printf "  ${WHITE}%-8s ${color}%s${NC}\n" "$count" "$url"
        done
    fi
    echo ""
    
    # 3. Status codes summary
    echo -e "${YELLOW}📊 HTTP Status Codes:${NC}"
    awk '{print $9}' "$temp_file" 2>/dev/null | \
        grep -v '^$' | \
        sort | uniq -c | sort -rn | \
        while read count status; do
            if [[ $status -ge 200 && $status -lt 300 ]]; then
                color=$GREEN
            elif [[ $status -ge 300 && $status -lt 400 ]]; then
                color=$BLUE
            elif [[ $status -ge 400 && $status -lt 500 ]]; then
                color=$YELLOW
            elif [[ $status -ge 500 ]]; then
                color=$RED
            else
                color=$WHITE
            fi
            printf "  ${WHITE}%-6s ${color}%s${NC}\n" "$count" "$status"
        done
    echo ""
    
    # 4. Request methods
    echo -e "${YELLOW}📝 Request Methods:${NC}"
    awk '{print $6}' "$temp_file" 2>/dev/null | \
        sed 's/"//g' | \
        grep -v '^$' | \
        sort | uniq -c | sort -rn | \
        while read count method; do
            printf "  ${WHITE}%-6s ${GREEN}%s${NC}\n" "$count" "$method"
        done
    echo ""
    
    # 5. Suspicious activity
    local suspicious=$(grep -c -E '\.(env|config|bak|sql|git|aws|pem|key|log|sh|py|db|conf|htaccess|htpasswd|yml|json|xml|yaml|ini|cfg|cnf|passwd|shadow|zip|tar|gz|rar)' "$temp_file" 2>/dev/null)
    if [ "$suspicious" -gt 0 ]; then
        echo -e "${RED}⚠️  Suspicious Activity: $suspicious attempts to access sensitive files${NC}"
        echo -e "${YELLOW}  Top suspicious files accessed:${NC}"
        grep -o -E '\/[^ ]*\.(env|config|bak|sql|git|aws|pem|key|log|sh|py|db|conf|htaccess|htpasswd|yml|json|xml|yaml|ini|cfg|cnf|passwd|shadow|zip|tar|gz|rar)' "$temp_file" 2>/dev/null | \
            sort | uniq -c | sort -rn | head -5 | \
            while read count file; do
                printf "    ${WHITE}%-6s ${RED}%s${NC}\n" "$count" "$file"
            done
        echo ""
    fi
    
    # 6. Brute force detection
    local login_attempts=$(grep -c -E '(wp-login|login|admin|signin|auth|xmlrpc)' "$temp_file" 2>/dev/null)
    if [ "$login_attempts" -gt 10 ]; then
        echo -e "${RED}🔴 Brute Force Detection: $login_attempts login attempts detected${NC}"
        echo -e "${YELLOW}  Top login URLs:${NC}"
        grep -o -E '\/[^ ]*(wp-login|login|admin|signin|auth|xmlrpc)[^ ]*' "$temp_file" 2>/dev/null | \
            sort | uniq -c | sort -rn | head -5 | \
            while read count url; do
                printf "    ${WHITE}%-6s ${RED}%s${NC}\n" "$count" "$url"
            done
        echo ""
    fi
    
    # 7. Top User Agents
    echo -e "${YELLOW}🤖 Top User Agents (Complete):${NC}"
    awk -F'"' '{print $6}' "$temp_file" 2>/dev/null | \
        grep -v '^\-$' | \
        grep -v '^$' | \
        sort | uniq -c | sort -rn | head -10 | \
        while read count agent; do
            printf "  ${WHITE}%-6s ${CYAN}%s${NC}\n" "$count" "$agent"
        done
    echo ""
    
    # Cleanup
    rm -f "$temp_file"
}

# Main function
analyze_domain() {
    local domain=$1
    
    if [ ! -d "$DOMLOG_PATH" ]; then
        echo -e "${RED}❌ Error: $DOMLOG_PATH not found${NC}"
        exit 1
    fi
    
    # Find all log files (excluding bytes_log)
    log_files_output=$(find_domain_logs "$domain")
    IFS=' ' read -ra log_files <<< "$log_files_output"
    
    if [ ${#log_files[@]} -eq 0 ]; then
        echo -e "${RED}❌ No log files found for domain: $domain${NC}"
        echo ""
        echo -e "${YELLOW}💡 Searching for similar domains...${NC}"
        find "$DOMLOG_PATH" -type f -name "*${domain:0:3}*" 2>/dev/null | head -10 | while read f; do
            if [ -f "$f" ] && [ -s "$f" ]; then
                filename=$(basename "$f")
                if [[ ! "$filename" == *"-bytes_log" ]]; then
                    echo -e "  ${CYAN}• $filename${NC}"
                fi
            fi
        done
        echo ""
        echo -e "${YELLOW}💡 Try:${NC}"
        echo -e "  ${WHITE}find $DOMLOG_PATH -type f -name '*.com*' | grep -v bytes_log | head -20${NC}"
        exit 1
    fi
    
    # Analyze combined logs
    analyze_combined_logs "$domain" "${log_files[@]}"
    
    # Final summary
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Combined analysis complete!${NC}"
    echo -e "${DIM}   All ${#log_files[@]} log files were combined into one report${NC}"
    echo ""
    
    echo -e "${DIM}💡 Quick commands:${NC}"
    echo -e "  ${DIM}tail -f $DOMLOG_PATH/${domain}-ssl_log${NC}"
    echo -e "  ${DIM}grep '404' $DOMLOG_PATH/${domain}* | wc -l${NC}"
}

# Interactive mode - get domain from user
get_domain_interactive() {
    echo -e "${BOLD}${CYAN}Enter the domain name to analyze:${NC} ${WHITE}(e.g., example.com)${NC}"
    echo -ne "${BOLD}${GREEN}➜ ${NC}"
    read -r domain_input
    
    # Remove leading/trailing whitespace
    domain_input=$(echo "$domain_input" | xargs)
    
    if [ -z "$domain_input" ]; then
        echo -e "${RED}❌ No domain entered. Exiting...${NC}"
        exit 1
    fi
    
    echo ""
    
    # Ask for monitoring option
    echo -e "${BOLD}${YELLOW}Select option:${NC}"
    echo -e "  ${WHITE}1)${NC} Full Analysis (Combined Report)"
    echo -e "  ${WHITE}2)${NC} Live Monitoring (Real-time requests)"
    echo -ne "${BOLD}${GREEN}➜ ${NC}"
    read -r option
    
    case $option in
        2|live|Live|LIVE)
            echo -e "${GREEN}▶ Starting live monitoring...${NC}"
            echo ""
            live_monitor "$domain_input"
            ;;
        *)
            analyze_domain "$domain_input"
            ;;
    esac
}

# Help function
show_help() {
    echo -e "${BOLD}${WHITE}Usage:${NC}"
    echo -e "  ${CYAN}$0${NC}                   ${DIM}(Interactive mode - will ask for domain)${NC}"
    echo -e "  ${CYAN}$0 <domain>${NC}          ${DIM}(Direct mode - analyze specified domain)${NC}"
    echo -e "  ${CYAN}$0 -h${NC}                ${DIM}(Show this help)${NC}"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  ${WHITE}$0${NC}"
    echo -e "  ${WHITE}$0 zyminex.com${NC}"
    echo -e "  ${WHITE}$0 example.com${NC}"
    echo ""
    echo -e "${YELLOW}Interactive Options:${NC}"
    echo -e "  ${WHITE}1)${NC} Full Analysis - Combined report of all logs"
    echo -e "  ${WHITE}2)${NC} Live Monitoring - Real-time request viewer"
    echo ""
    echo -e "${YELLOW}Features:${NC}"
    echo -e "  ${WHITE}•${NC} ${GREEN}Combines ALL log files into ONE report${NC}"
    echo -e "  ${WHITE}•${NC} ${RED}Live monitoring with real-time updates${NC}"
    echo -e "  ${WHITE}•${NC} Shows list of all combined log files with details"
    echo -e "  ${WHITE}•${NC} Shows complete User-Agent strings (no truncation)"
    echo -e "  ${WHITE}•${NC} Shows complete URLs (no truncation)"
    echo -e "  ${WHITE}•${NC} ${GREEN}Shows TOP 20 URLs only${NC}"
    echo -e "  ${WHITE}•${NC} Shows today's request count"
    echo -e "  ${WHITE}•${NC} Detects suspicious activity and brute force"
    echo -e "  ${WHITE}•${NC} Shows top IPs, status codes, and methods"
    echo -e "  ${WHITE}•${NC} ${GREEN}EXCLUDES bytes_log files (bandwidth logs)${NC}"
}

# Main execution
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    print_header
    show_help
    exit 0
fi

print_header

if [ $# -eq 0 ]; then
    # Interactive mode - ask for domain
    get_domain_interactive
else
    # Check if domain is "live" or "monitor" for direct live mode
    if [ "$2" = "live" ] || [ "$2" = "monitor" ]; then
        print_header
        echo -e "${GREEN}▶ Starting live monitoring for: ${CYAN}$1${NC}"
        echo ""
        live_monitor "$1"
    else
        # Direct mode - use first argument as domain
        analyze_domain "$1"
    fi
fi
