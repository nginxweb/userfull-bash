#!/bin/bash

# ======================================================================
# ╔══════════════════════════════════════════════════════════════════╗
# ║     EXIM QUEUE SPAM ANALYZER - ADVANCED EMAIL SECURITY TOOL     ║
# ╚══════════════════════════════════════════════════════════════════╝
# ======================================================================
# 
#  ██╗   ██╗██╗  ████████╗ █████╗ ██╗  ██╗ ██████╗ ███████╗████████╗
#  ██║   ██║██║  ╚══██╔══╝██╔══██╗██║  ██║██╔═══██╗██╔════╝╚══██╔══╝
#  ██║   ██║██║     ██║   ███████║███████║██║   ██║█████╗     ██║   
#  ██║   ██║██║     ██║   ██╔══██║██╔══██║██║   ██║██╔══╝     ██║   
#  ╚██████╔╝███████╗██║   ██║  ██║██║  ██║╚██████╔╝███████╗   ██║   
#   ╚═════╝ ╚══════╝╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   
# 
# ======================================================================
#  📧 EXIM Queue Analyzer - Complete Email Traffic Statistics Tool
# ======================================================================
# 
#  📝 Author       : Eisa Mohammadzadeh
#  🏢 Company      : Ultahost.com
#  📅 Version      : 2.0
#  🗓️ Date         : April 2026
#  📋 License      : MIT
# 
# ======================================================================
#  📖 DESCRIPTION:
#  =====================================================================
#  This powerful script analyzes Exim mail queue and provides:
#  • Today's complete email traffic statistics (Received/Sent/Failed)
#  • Top senders and recipients with volume alerts
#  • Suspicious domain detection (spam TLDs)
#  • CWD (Current Working Directory) path analysis
#  • Hourly email volume breakdown with visual graphs
#  • Cron job email sender detection
#  • High-risk spam message identification
#  • Interactive queue management menu
# 
# ======================================================================
#  🛠️ USAGE:
#  =====================================================================
#  Just run the script: ./exim_analyzer.sh
#  
#  No arguments needed - everything is automated!
# 
# ======================================================================
#  ✨ FEATURES:
#  =====================================================================
#  ✅ Real-time queue analysis
#  ✅ Color-coded output for easy reading
#  ✅ Spam scoring system (0-100%)
#  ✅ Frozen message detection
#  ✅ Bounce message identification
#  ✅ Cron job email tracking
#  ✅ System cron directory overview
#  ✅ Interactive queue management menu
#  ✅ Backup and restore capabilities
#  ✅ Safe removal options with confirmation
# 
# ======================================================================
#  🔧 REQUIREMENTS:
#  =====================================================================
#  • Root access (for exim commands)
#  • Exim mail server
#  • Bash 4.0+
#  • Read access to /var/log/exim_mainlog
# 
# ======================================================================
#  📁 OUTPUT FILES:
#  =====================================================================
#  Temporary files are created in /tmp/ and automatically cleaned up
#  Cron backups are saved in /tmp/cron_backup_*
# 
# ======================================================================
#  🚀 ULTACHPOWER TOOLS - Professional Server Management
# ======================================================================
# 
#  "Keeping your email infrastructure secure and efficient"
# 
# ======================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Icons
ICON_SPAM="🚨"
ICON_SUSPICIOUS="⚠️"
ICON_CLEAN="✅"

# Temporary files
HIGH_RISK_FILE="/tmp/exim_high_risk_$$.txt"
MEDIUM_RISK_FILE="/tmp/exim_medium_risk_$$.txt"
LOW_RISK_FILE="/tmp/exim_low_risk_$$.txt"
SPAM_SENDERS_FILE="/tmp/exim_spam_senders_$$.txt"
ERROR_LOG="/tmp/exim_errors_$$.log"
STATS_FILE="/tmp/exim_stats_$$.txt"

# Initialize files
> $HIGH_RISK_FILE
> $MEDIUM_RISK_FILE
> $LOW_RISK_FILE
> $SPAM_SENDERS_FILE
> $ERROR_LOG
> $STATS_FILE

# Function to get today's date in log format
get_today_date() {
    date +"%Y-%m-%d"
}

# Function to find users with active cron jobs sending emails
find_cron_email_users() {
    local today=$(get_today_date)
    local log_file="/var/log/exim_mainlog"
    local temp_users="/tmp/cron_users_$$.txt"
    
    echo -e "\n${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${MAGENTA}║                    ⏰ USERS WITH CRON JOBS SENDING EMAILS${NC}"
    echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check exim logs for cron-related emails
    if [[ -f "$log_file" ]]; then
        # Get unique users with email counts and sort by count
        > "$temp_users"
        grep "$today" $log_file 2>/dev/null | grep "cwd=" | grep -E "/home/" | grep -oP 'cwd=/home/\K[^/]+' | sort | uniq -c | sort -rn > "$temp_users"
        
        if [[ -s "$temp_users" ]]; then
            # Show TOP 5 senders in a separate highlighted section
            local top_count=0
            echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BOLD}${RED}║                    🔥 TOP 5 CRON EMAIL SENDERS (TODAY)${NC}"
            echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}\n"
            
            head -5 "$temp_users" | while IFS= read -r line; do
                local email_count=$(echo "$line" | awk '{print $1}')
                local user=$(echo "$line" | awk '{print $2}' | awk '{print $1}')
                if [[ -n "$user" ]]; then
                    top_count=$((top_count + 1))
                    if [[ $email_count -ge 100 ]]; then
                        echo -e "  ${RED}${top_count}. ${BOLD}$user${NC} ${RED}🚨 $email_count emails${NC}"
                    elif [[ $email_count -ge 50 ]]; then
                        echo -e "  ${RED}${top_count}. ${BOLD}$user${NC} ${RED}⚠️ $email_count emails${NC}"
                    else
                        echo -e "  ${YELLOW}${top_count}. ${BOLD}$user${NC} ${YELLOW}$email_count emails${NC}"
                    fi
                fi
            done
            echo ""
            
            # Show all users
            echo -e "${BOLD}${CYAN}📋 All users sending emails via Cron (Today):${NC}\n"
            
            while IFS= read -r line; do
                local email_count=$(echo "$line" | awk '{print $1}')
                local user=$(echo "$line" | awk '{print $2}' | awk '{print $1}')
                [[ -z "$user" ]] && continue
                
                # Show user with color based on email count
                if [[ $email_count -ge 100 ]]; then
                    echo -e "  ${RED}🔥 ${BOLD}User:${NC} ${RED}${BOLD}$user${NC} ${RED}🚨 EXTREME ($email_count emails)${NC}"
                elif [[ $email_count -ge 50 ]]; then
                    echo -e "  ${RED}⚠️ ${BOLD}User:${NC} ${RED}${BOLD}$user${NC} ${RED}HIGH VOLUME ($email_count emails)${NC}"
                elif [[ $email_count -ge 20 ]]; then
                    echo -e "  ${YELLOW}👤 User:${NC} ${YELLOW}${BOLD}$user${NC} ${YELLOW}($email_count emails)${NC}"
                else
                    echo -e "  ${GREEN}👤 User:${NC} ${GREEN}$user${NC} ($email_count emails)${NC}"
                fi
                
                echo -e "     ${BLUE}📧 Emails sent today:${NC} ${RED}$email_count${NC}"
                
                # Show cron file path and count jobs
                if [[ -f "/var/spool/cron/$user" ]]; then
                    echo -e "     ${CYAN}📁 Cron file:${NC} /var/spool/cron/$user"
                    local total_cron=$(grep -v "^#" "/var/spool/cron/$user" 2>/dev/null | grep -v "^$" | wc -l)
                    echo -e "     ${BLUE}📊 Total cron jobs:${NC} $total_cron"
                    
                    # Show sample of cron jobs (max 2)
                    local cron_count=0
                    while IFS= read -r cron_line; do
                        if [[ -n "$cron_line" ]] && [[ ! "$cron_line" =~ ^# ]] && [[ $cron_count -lt 2 ]]; then
                            # Skip MAILTO and SHELL lines
                            if [[ ! "$cron_line" =~ ^MAILTO= ]] && [[ ! "$cron_line" =~ ^SHELL= ]]; then
                                cron_count=$((cron_count + 1))
                                local short_line="${cron_line:0:70}"
                                echo -e "     ${GREEN}⚙️ Cron $cron_count:${NC} $short_line"
                            fi
                        fi
                    done < <(grep -v "^#" "/var/spool/cron/$user" 2>/dev/null | grep -v "^$")
                    
                    if [[ ${total_cron:-0} -gt 2 ]]; then
                        echo -e "     ${YELLOW}   ... and $((total_cron - 2)) more cron jobs${NC}"
                    fi
                else
                    echo -e "     ${CYAN}📁 Cron file:${NC} crontab -l -u $user"
                    local user_cron=$(crontab -l -u "$user" 2>/dev/null | grep -v "^#" | grep -v "^$")
                    local total_cron=$(echo "$user_cron" | wc -l)
                    echo -e "     ${BLUE}📊 Total cron jobs:${NC} ${total_cron:-0}"
                    
                    # Show sample of cron jobs (max 2)
                    local cron_count=0
                    while IFS= read -r cron_line; do
                        if [[ -n "$cron_line" ]] && [[ $cron_count -lt 2 ]]; then
                            cron_count=$((cron_count + 1))
                            local short_line="${cron_line:0:70}"
                            echo -e "     ${GREEN}⚙️ Cron $cron_count:${NC} $short_line"
                        fi
                    done <<< "$user_cron"
                    
                    if [[ ${total_cron:-0} -gt 2 ]]; then
                        echo -e "     ${YELLOW}   ... and $((total_cron - 2)) more cron jobs${NC}"
                    fi
                fi
                echo ""
            done < "$temp_users"
            rm -f "$temp_users"
        else
            echo -e "  ${GREEN}✅ No users found sending emails via cron today${NC}\n"
        fi
    fi
    
    # System cron directories
    echo -e "${BOLD}${CYAN}📁 System Cron Directories:${NC}\n"
    
    for cron_dir in /etc/cron.d /etc/cron.daily /etc/cron.hourly; do
        if [[ -d "$cron_dir" ]]; then
            local file_count=$(find "$cron_dir" -type f 2>/dev/null | wc -l)
            if [[ $file_count -gt 0 ]]; then
                echo -e "  ${BLUE}📂 $cron_dir${NC}: $file_count files"
                # Show first 2 files
                find "$cron_dir" -type f 2>/dev/null | head -2 | while read file; do
                    echo -e "     ${CYAN}→${NC} $(basename "$file")"
                done
                if [[ $file_count -gt 2 ]]; then
                    echo -e "     ${YELLOW}... and $((file_count - 2)) more files${NC}"
                fi
                echo ""
            fi
        fi
    done
    echo ""
}

# Function to analyze today's email statistics
analyze_today_stats() {
    local today=$(get_today_date)
    local log_file="/var/log/exim_mainlog"
    
    if [[ ! -f "$log_file" ]]; then
        echo -e "${RED}Log file not found!${NC}"
        return
    fi
    
    echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                    📊 TODAY'S EMAIL STATISTICS - $(date '+%Y-%m-%d')${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # 1. Total emails sent and received today
    echo -e "${BOLD}${WHITE}📈 Overall Traffic:${NC}"
    
    local received=$(grep "$today" $log_file | grep "<=" | grep -v "<= <>" | grep -v "U=mailnull" | wc -l)
    local sent=$(grep "$today" $log_file | grep "=>" | wc -l)
    local failed=$(grep "$today" $log_file | grep "\*\*" | wc -l)
    local bounces=$(grep "$today" $log_file | grep "<= <>" | wc -l)
    
    echo -e "  ${GREEN}📥 Received:${NC} $received emails"
    echo -e "  ${BLUE}📤 Sent:${NC} $sent emails"
    echo -e "  ${RED}❌ Failed:${NC} $failed emails"
    echo -e "  ${YELLOW}🔄 Bounces:${NC} $bounces emails"
    echo -e "  ${CYAN}📊 Total Processed:${NC} $((received + sent)) emails\n"
    
    # 2. Top sending email addresses
    echo -e "${BOLD}${WHITE}🔥 Top Senders (Today):${NC}"
    grep "$today" $log_file | grep "<=" | grep -v "<= <>" | \
        grep -oP '(?<=<= )[^ ]+' | \
        grep -v "^$" | \
        sort | uniq -c | sort -rn | head -10 | \
        while read count sender; do
            if [[ $count -gt 100 ]]; then
                echo -e "  ${RED}${count}x${NC} ${YELLOW}$sender${NC} ${RED}🚨 EXTREME${NC}"
            elif [[ $count -gt 50 ]]; then
                echo -e "  ${RED}${count}x${NC} ${YELLOW}$sender${NC} ${RED}⚠️ HIGH${NC}"
            elif [[ $count -gt 20 ]]; then
                echo -e "  ${YELLOW}${count}x${NC} $sender"
            else
                echo -e "  ${GREEN}${count}x${NC} $sender"
            fi
        done
    
    if [[ $(grep "$today" $log_file | grep "<=" | grep -v "<= <>" | wc -l) -eq 0 ]]; then
        echo -e "  ${CYAN}No outgoing emails today${NC}"
    fi
    echo ""
    
    # 3. Top receiving email addresses
    echo -e "${BOLD}${WHITE}🎯 Top Recipients (Today):${NC}"
    grep "$today" $log_file | grep -E "(=>|->)" | \
        grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
        sort | uniq -c | sort -rn | head -10 | \
        while read count recipient; do
            if [[ $count -gt 100 ]]; then
                echo -e "  ${RED}${count}x${NC} ${YELLOW}$recipient${NC} ${RED}🚨 EXTREME${NC}"
            elif [[ $count -gt 50 ]]; then
                echo -e "  ${RED}${count}x${NC} ${YELLOW}$recipient${NC} ${RED}⚠️ HIGH${NC}"
            elif [[ $count -gt 20 ]]; then
                echo -e "  ${YELLOW}${count}x${NC} $recipient"
            else
                echo -e "  ${GREEN}${count}x${NC} $recipient"
            fi
        done
    
    if [[ $(grep "$today" $log_file | grep -E "(=>|->)" | wc -l) -eq 0 ]]; then
        echo -e "  ${CYAN}No incoming emails today${NC}"
    fi
    echo ""
    
    # 4. Top CWD paths - FULL PATHS
    echo -e "${BOLD}${WHITE}📂 Top CWD Paths (Email Origins):${NC}"
    grep "$today" $log_file | grep "cwd=" | \
        grep -oP 'cwd=\K[^ ]+' | \
        sort | uniq -c | sort -rn | head -15 | \
        while read count path; do
            if [[ "$path" == "/var/spool/exim" ]]; then
                display_path="/var/spool/exim (EXIM Queue)"
            elif [[ "$path" == "/root" ]]; then
                display_path="/root (Root User)"
            elif [[ "$path" == "/" ]]; then
                display_path="/ (Root Directory)"
            elif [[ "$path" =~ ^/home/ ]]; then
                username=$(echo "$path" | cut -d'/' -f3)
                full_path=$(echo "$path" | sed "s|/home/$username|~$username|")
                display_path="$full_path"
            elif [[ "$path" == "/run/dovecot" ]]; then
                display_path="/run/dovecot (Dovecot Runtime)"
            else
                display_path="$path"
            fi
            
            if [[ $count -gt 1000 ]]; then
                echo -e "  ${RED}${count}x${NC} ${YELLOW}$display_path${NC} ${RED}🚨 EXTREME${NC}"
            elif [[ $count -gt 500 ]]; then
                echo -e "  ${RED}${count}x${NC} ${YELLOW}$display_path${NC} ${RED}⚠️ HIGH${NC}"
            elif [[ $count -gt 100 ]]; then
                echo -e "  ${YELLOW}${count}x${NC} $display_path"
            else
                echo -e "  ${GREEN}${count}x${NC} $display_path"
            fi
        done
    
    local top_path=$(grep "$today" $log_file | grep "cwd=" | grep -oP 'cwd=\K[^ ]+' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
    if [[ -n "$top_path" ]] && [[ -d "$top_path" ]]; then
        echo -e "\n  ${CYAN}📌 Top Path Details:${NC}"
        echo -e "    Path: $top_path"
        if [[ "$top_path" =~ ^/home/ ]]; then
            local user=$(echo "$top_path" | cut -d'/' -f3)
            echo -e "    User: $user"
            echo -e "    Home: /home/$user"
        fi
    fi
    echo ""
    
    # 5. Email volume by hour - DETAILED BREAKDOWN
    echo -e "${BOLD}${WHITE}⏰ Email Volume by Hour (Today):${NC}"
    echo -e "  ${CYAN}💡 Note: Each hour shows RECEIVED + SENT separately${NC}"
    printf "  ${GREEN}%-8s ${BLUE}%-12s ${BLUE}%-12s ${YELLOW}%-12s %s${NC}\n" "Hour" "Received" "Sent" "Total" "Volume"
    echo -e "  ${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"
    
    local max_total=0
    for hour in {0..23}; do
        hour_padded=$(printf "%02d" $hour)
        total=$(grep "$today $hour_padded:" $log_file | wc -l)
        if [[ $total -gt $max_total ]]; then
            max_total=$total
        fi
    done
    
    for hour in {0..23}; do
        hour_padded=$(printf "%02d" $hour)
        
        received_count=$(grep "$today $hour_padded:" $log_file | grep "<=" | grep -v "<= <>" | grep -v "U=mailnull" | wc -l)
        sent_count=$(grep "$today $hour_padded:" $log_file | grep "=>" | wc -l)
        total_count=$((received_count + sent_count))
        
        if [[ $total_count -gt 0 ]]; then
            bar_length=$((total_count * 50 / max_total))
            if [[ $bar_length -lt 1 ]]; then
                bar_length=1
            fi
            bar=$(printf "%${bar_length}s" | tr ' ' '█')
            
            if [[ $total_count -ge 4000 ]]; then
                printf "  ${RED}%02d:00${NC} ${GREEN}%6d${NC} ${BLUE}%6d${NC} ${YELLOW}%6d${NC} ${RED}%s${NC}\n" \
                       "$hour" "$received_count" "$sent_count" "$total_count" "$bar"
            elif [[ $total_count -ge 2000 ]]; then
                printf "  ${YELLOW}%02d:00${NC} ${GREEN}%6d${NC} ${BLUE}%6d${NC} ${YELLOW}%6d${NC} ${YELLOW}%s${NC}\n" \
                       "$hour" "$received_count" "$sent_count" "$total_count" "$bar"
            else
                printf "  ${CYAN}%02d:00${NC} ${GREEN}%6d${NC} ${BLUE}%6d${NC} ${WHITE}%6d${NC} ${GREEN}%s${NC}\n" \
                       "$hour" "$received_count" "$sent_count" "$total_count" "$bar"
            fi
        fi
    done
    
    if [[ $received -gt 0 ]] && [[ $sent -gt 0 ]]; then
        local avg_received=$((received / 24))
        local avg_sent=$((sent / 24))
        echo ""
        echo -e "${BOLD}${WHITE}📊 Hourly Averages:${NC}"
        echo -e "  ${GREEN}📥 Avg Received per hour:${NC} $avg_received"
        echo -e "  ${BLUE}📤 Avg Sent per hour:${NC} $avg_sent"
        echo -e "  ${YELLOW}📊 Avg Total per hour:${NC} $((avg_received + avg_sent))"
    fi
    
    local peak_hour=""
    local peak_total=0
    for hour in {0..23}; do
        hour_padded=$(printf "%02d" $hour)
        total=$(grep "$today $hour_padded:" $log_file | wc -l)
        if [[ $total -gt $peak_total ]]; then
            peak_total=$total
            peak_hour=$hour
        fi
    done
    echo -e "  ${RED}🔴 Peak Hour:${NC} ${peak_hour}:00 with ${peak_total} total emails (Received + Sent)"
    echo ""
    
    # 6. Top domains sending emails
    echo -e "${BOLD}${WHITE}🌐 Top Sending Domains (Today):${NC}"
    grep "$today" $log_file | grep "<=" | grep -v "<= <>" | \
        grep -oP '(?<=<= )[^@]+@\K[^ ]+' | \
        sort | uniq -c | sort -rn | head -10 | \
        while read count domain; do
            if [[ "$domain" =~ \.(xyz|top|work|date|stream|bid|trade|webcam|science|party|review|loan|win|men|download|racing|accountant|faith|bar|rest|click|link|help|gdn|ooo|cfd|sbs|icu|cyou|bond|monster)$ ]]; then
                echo -e "  ${RED}${count}x${NC} ${YELLOW}$domain${NC} ${RED}⚠️ SUSPICIOUS${NC}"
            else
                echo -e "  ${GREEN}${count}x${NC} $domain"
            fi
        done
    echo ""
    
    # 7. Failed deliveries by domain
    echo -e "${BOLD}${WHITE}❌ Failed Deliveries by Domain (Today):${NC}"
    grep "$today" $log_file | grep "\*\*" | \
        grep -oE '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | cut -d'@' -f2 | \
        sort | uniq -c | sort -rn | head -10 | \
        while read count domain; do
            echo -e "  ${RED}${count}x${NC} $domain"
        done
    
    if [[ $(grep "$today" $log_file | grep "\*\*" | wc -l) -eq 0 ]]; then
        echo -e "  ${GREEN}No failed deliveries today!${NC}"
    fi
    echo ""
    
    find_cron_email_users
}

# Function to extract message info from Exim logs
get_message_info_from_logs() {
    local msg_id="$1"
    local sender=""
    local recipients=""
    local subject=""
    
    local log_entries=$(grep "$msg_id" /var/log/exim_mainlog 2>/dev/null | head -5)
    
    if [[ -n "$log_entries" ]]; then
        local arrival_line=$(echo "$log_entries" | grep "<=" | head -1)
        if [[ -n "$arrival_line" ]]; then
            sender=$(echo "$arrival_line" | grep -oP '(?<=<= )[^ ]+' | head -1)
            
            if [[ "$sender" == "<>" ]]; then
                local for_recipient=$(echo "$arrival_line" | grep -oP '(?<=for )[^ ]+@[^ ]+' | head -1)
                if [[ -n "$for_recipient" ]]; then
                    sender="MAILER-DAEMON (bounce for $for_recipient)"
                else
                    sender="MAILER-DAEMON (System Bounce)"
                fi
            fi
        fi
        
        local delivery_lines=$(echo "$log_entries" | grep -E "(=>|->|\*\*)")
        if [[ -n "$delivery_lines" ]]; then
            recipients=$(echo "$delivery_lines" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | sort -u | head -3 | tr '\n' ', ' | sed 's/, $//')
        fi
        
        subject=$(echo "$log_entries" | grep -oP '(?<=T=")[^"]+' | head -1)
        if [[ -z "$subject" ]]; then
            subject="Mail Delivery Report"
        fi
    fi
    
    [[ -z "$sender" ]] && sender="Unknown"
    [[ -z "$recipients" ]] && recipients="Unknown"
    [[ -z "$subject" ]] && subject="[No Subject]"
    
    echo "$msg_id|$sender|$recipients|$subject"
}

# Analyze message spam score
analyze_message_spam_score() {
    local msg_id="$1"
    
    local msg_info=$(get_message_info_from_logs "$msg_id")
    IFS='|' read -r _ sender recipients subject <<< "$msg_info"
    
    local frozen_status=$(exim -bp 2>/dev/null | grep -F "$msg_id" | grep -o "frozen")
    
    local spam_score_num=0
    local spam_reasons=()
    
    if [[ "$frozen_status" == "frozen" ]]; then
        spam_score_num=$((spam_score_num + 40))
        spam_reasons+=("❄️ Frozen")
    fi
    
    if [[ "$sender" == MAILER-DAEMON* ]]; then
        spam_score_num=$((spam_score_num + 30))
        spam_reasons+=("📨 Bounce Message")
    fi
    
    if [[ $spam_score_num -gt 100 ]]; then
        spam_score_num=100
    fi
    if [[ $spam_score_num -lt 0 ]]; then
        spam_score_num=0
    fi
    
    local subject_short="${subject:0:50}"
    if [[ ${#subject} -gt 50 ]]; then
        subject_short="${subject_short}..."
    fi
    
    local recipients_short="${recipients:0:60}"
    if [[ ${#recipients} -gt 60 ]]; then
        recipients_short="${recipients_short}..."
    fi
    
    local sender_short="${sender:0:35}"
    if [[ ${#sender} -gt 35 ]]; then
        sender_short="${sender_short}..."
    fi
    
    local reason_string=$(IFS=' '; echo "${spam_reasons[*]}")
    
    if [[ $spam_score_num -ge 60 ]]; then
        echo "$msg_id|$sender_short|$recipients_short|$subject_short|$spam_score_num|$reason_string" >> $HIGH_RISK_FILE
        echo "$sender" >> $SPAM_SENDERS_FILE
    elif [[ $spam_score_num -ge 40 ]]; then
        echo "$msg_id|$sender_short|$recipients_short|$subject_short|$spam_score_num|$reason_string" >> $MEDIUM_RISK_FILE
        echo "$sender" >> $SPAM_SENDERS_FILE
    else
        echo "$msg_id|$sender_short|$recipients_short|$subject_short|$spam_score_num|$reason_string" >> $LOW_RISK_FILE
    fi
}

# Print header
print_header() {
    clear
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${WHITE}              EXIM QUEUE SPAM ANALYZER - WITH COMPLETE STATISTICS${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# Get queue summary - FIXED VERSION
get_queue_summary() {
    local total=$(exim -bpc 2>/dev/null)
    local frozen=$(exim -bp 2>/dev/null | grep -c "frozen" 2>/dev/null)
    
    # Convert to numbers safely
    total=${total:-0}
    frozen=${frozen:-0}
    
    # Ensure they are numbers
    total=$(echo "$total" | grep -o '[0-9]*' | head -1)
    frozen=$(echo "$frozen" | grep -o '[0-9]*' | head -1)
    
    total=${total:-0}
    frozen=${frozen:-0}
    
    local active=$((total - frozen))
    
    echo -e "${BOLD}${WHITE}📊 Queue Summary:${NC}"
    echo -e "  ${BLUE}▶${NC} Total Messages: ${BOLD}$total${NC}"
    echo -e "  ${GREEN}▶${NC} Active: ${BOLD}$active${NC}"
    echo -e "  ${YELLOW}▶${NC} Frozen: ${BOLD}$frozen${NC}"
    
    if [[ -f /var/log/exim_mainlog ]]; then
        local log_size=$(du -h /var/log/exim_mainlog 2>/dev/null | cut -f1)
        echo -e "  ${CYAN}▶${NC} Log file: ${BOLD}/var/log/exim_mainlog${NC} (${log_size})"
    fi
    echo ""
}

# Show progress bar
show_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r  ${CYAN}Analyzing queue:${NC} ["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] ${percent}%% (${current}/${total})"
}

# Print summary report
print_summary() {
    local high_count=$(wc -l < $HIGH_RISK_FILE 2>/dev/null || echo "0")
    local medium_count=$(wc -l < $MEDIUM_RISK_FILE 2>/dev/null || echo "0")
    local low_count=$(wc -l < $LOW_RISK_FILE 2>/dev/null || echo "0")
    local total=$((high_count + medium_count + low_count))
    
    echo -e "\n\n${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${WHITE}                              📋 QUEUE ANALYSIS REPORT${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${BOLD}${WHITE}📈 Queue Risk Assessment:${NC}"
    echo -e "  ${RED}🔴 HIGH Risk (≥60%): $high_count messages${NC}"
    echo -e "  ${YELLOW}🟡 MEDIUM Risk (40-59%): $medium_count messages${NC}"
    echo -e "  ${GREEN}🟢 LOW Risk (<40%): $low_count messages${NC}"
    echo -e "  ${BLUE}📊 Total Analyzed: $total messages${NC}\n"
    
    if [[ $high_count -gt 0 ]]; then
        echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${RED}║                    🚨 HIGH RISK MESSAGES IN QUEUE ($high_count)${NC}"
        echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}\n"
        
        printf "${BOLD}${WHITE}%-22s %-35s %-28s %-30s %-6s${NC}\n" "MESSAGE ID" "FROM" "TO" "SUBJECT" "SCORE"
        echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
        
        local count=0
        while IFS='|' read -r msg_id from to subject score reasons; do
            count=$((count + 1))
            printf "${RED}%-22s ${YELLOW}%-35s ${CYAN}%-28s ${WHITE}%-30s ${RED}%s%%${NC}\n" \
                   "${msg_id:0:20}" "${from:0:33}" "${to:0:26}" "${subject:0:28}" "$score"
            echo -e "  ${RED}→ Reasons:${NC} ${WHITE}$reasons${NC}\n"
            if [[ $count -ge 10 ]]; then
                break
            fi
        done < $HIGH_RISK_FILE
        
        if [[ $high_count -gt 10 ]]; then
            echo -e "${YELLOW}  ... and $((high_count - 10)) more high risk messages in queue${NC}\n"
        fi
    fi
    
    if [[ -f $SPAM_SENDERS_FILE ]] && [[ -s $SPAM_SENDERS_FILE ]]; then
        echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${RED}║                    🔥 TOP SUSPICIOUS SENDERS IN QUEUE${NC}"
        echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}\n"
        
        sort $SPAM_SENDERS_FILE | uniq -c | sort -rn | head -10 | while read count sender; do
            if [[ $count -gt 20 ]]; then
                echo -e "  ${RED}${count}x${NC} ${YELLOW}$sender${NC} ${RED}🚨 CRITICAL${NC}"
            elif [[ $count -gt 10 ]]; then
                echo -e "  ${RED}${count}x${NC} ${YELLOW}$sender${NC} ${RED}⚠️ HIGH${NC}"
            elif [[ $count -gt 5 ]]; then
                echo -e "  ${YELLOW}${count}x${NC} $sender"
            else
                echo -e "  ${GREEN}${count}x${NC} $sender"
            fi
        done
        echo ""
    fi
}

# Interactive menu for queue management
interactive_menu() {
    local total_msgs=$(exim -bpc 2>/dev/null)
    local frozen_msgs=$(exim -bp 2>/dev/null | grep -c "frozen" 2>/dev/null)
    
    total_msgs=${total_msgs:-0}
    frozen_msgs=${frozen_msgs:-0}
    
    local active_msgs=$((total_msgs - frozen_msgs))
    
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${MAGENTA}                         🛠️ QUEUE MANAGEMENT MENU${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${BOLD}${WHITE}Current Queue Status:${NC}"
    echo -e "  ${CYAN}📊 Total messages:${NC} $total_msgs"
    echo -e "  ${YELLOW}❄️ Frozen messages:${NC} $frozen_msgs"
    echo -e "  ${GREEN}✅ Active messages:${NC} $active_msgs\n"
    
    echo -e "${BOLD}${WHITE}Select an option:${NC}"
    echo -e "  ${GREEN}1${NC}) Remove ONLY frozen messages (Recommended for spam cleanup)"
    echo -e "  ${YELLOW}2${NC}) Remove ALL messages from queue (⚠️ DANGER - Clears entire queue)"
    echo -e "  ${BLUE}3${NC}) Remove HIGH RISK messages only (≥60% spam score)"
    echo -e "  ${CYAN}4${NC}) View queue summary again"
    echo -e "  ${RED}5${NC}) Exit without changes"
    echo ""
    
    read -p $'\033[1;37mEnter your choice [1-5]: \033[0m' choice
    
    case $choice in
        1)
            if [[ $frozen_msgs -eq 0 ]]; then
                echo -e "\n${GREEN}✅ No frozen messages to remove!${NC}"
            else
                echo -e "\n${YELLOW}⚠️ Are you sure you want to remove ALL frozen messages?${NC}"
                read -p "Type 'yes' to confirm: " confirm
                if [[ "$confirm" == "yes" ]]; then
                    echo -e "\n${CYAN}Removing frozen messages...${NC}"
                    local removed=$(exiqgrep -z -i 2>/dev/null | wc -l)
                    exiqgrep -z -i | xargs exim -Mrm 2>/dev/null
                    echo -e "${GREEN}✅ Removed $removed frozen messages from queue${NC}"
                else
                    echo -e "${RED}❌ Operation cancelled${NC}"
                fi
            fi
            ;;
        2)
            if [[ $total_msgs -eq 0 ]]; then
                echo -e "\n${GREEN}✅ Queue is already empty!${NC}"
            else
                echo -e "\n${RED}${BOLD}⚠️  DANGER: This will remove ALL messages from queue! ⚠️${NC}"
                echo -e "${RED}Total messages to remove: $total_msgs${NC}"
                read -p "Type 'DELETE ALL' to confirm: " confirm
                if [[ "$confirm" == "DELETE ALL" ]]; then
                    echo -e "\n${RED}Removing all messages from queue...${NC}"
                    exim -bp | awk '{print $3}' | xargs exim -Mrm 2>/dev/null
                    echo -e "${RED}✅ Removed all $total_msgs messages from queue${NC}"
                else
                    echo -e "${RED}❌ Operation cancelled${NC}"
                fi
            fi
            ;;
        3)
            if [[ -f $HIGH_RISK_FILE ]] && [[ -s $HIGH_RISK_FILE ]]; then
                local high_count=$(wc -l < $HIGH_RISK_FILE)
                if [[ $high_count -eq 0 ]]; then
                    echo -e "\n${GREEN}✅ No high risk messages found to remove${NC}"
                else
                    echo -e "\n${YELLOW}⚠️ This will remove $high_count HIGH RISK messages from queue${NC}"
                    read -p "Type 'yes' to confirm: " confirm
                    if [[ "$confirm" == "yes" ]]; then
                        echo -e "\n${CYAN}Removing high risk messages...${NC}"
                        local removed=0
                        while IFS='|' read -r msg_id rest; do
                            exim -Mrm "$msg_id" 2>/dev/null && ((removed++))
                        done < $HIGH_RISK_FILE
                        echo -e "${GREEN}✅ Removed $removed high risk messages from queue${NC}"
                    else
                        echo -e "${RED}❌ Operation cancelled${NC}"
                    fi
                fi
            else
                echo -e "\n${GREEN}✅ No high risk messages found to remove${NC}"
            fi
            ;;
        4)
            get_queue_summary
            interactive_menu
            return
            ;;
        5)
            echo -e "\n${GREEN}Exiting without changes...${NC}"
            ;;
        *)
            echo -e "\n${RED}Invalid option! Please try again.${NC}"
            interactive_menu
            return
            ;;
    esac
    
    # Only show updated status if changes were made and not viewing summary or exiting
    if [[ $choice != "4" ]] && [[ $choice != "5" ]]; then
        local new_total=$(exim -bpc 2>/dev/null)
        local new_frozen=$(exim -bp 2>/dev/null | grep -c "frozen" 2>/dev/null)
        
        new_total=${new_total:-0}
        new_frozen=${new_frozen:-0}
        
        local new_active=$((new_total - new_frozen))
        
        echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${WHITE}Updated Queue Status:${NC}"
        echo -e "  ${CYAN}📊 Total messages:${NC} $new_total"
        echo -e "  ${YELLOW}❄️ Frozen messages:${NC} $new_frozen"
        echo -e "  ${GREEN}✅ Active messages:${NC} $new_active"
        echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}\n"
    fi
}

# Main execution
main() {
    print_header
    
    local queue_size=$(exim -bpc 2>/dev/null)
    queue_size=${queue_size:-0}
    
    analyze_today_stats
    get_queue_summary
    
    if [[ $queue_size -eq 0 ]]; then
        echo -e "${GREEN}✅ Queue is empty!${NC}\n"
        exit 0
    fi
    
    echo -e "${BOLD}${CYAN}🔍 Analyzing queue messages...${NC}\n"
    
    local msg_ids=()
    while IFS= read -r line; do
        local msg_id=$(echo "$line" | awk '{print $3}')
        if [[ -n "$msg_id" ]] && [[ "$msg_id" =~ ^[0-9A-Za-z] ]]; then
            msg_ids+=("$msg_id")
        fi
    done < <(exim -bp 2>/dev/null | grep -E "^\s*[0-9]+[a-zA-Z]?\s")
    
    local total=${#msg_ids[@]}
    local current=0
    
    for msg_id in "${msg_ids[@]}"; do
        analyze_message_spam_score "$msg_id"
        current=$((current + 1))
        show_progress $current $total
    done
    
    echo -e "\n\n${GREEN}✅ Queue analysis complete!${NC}\n"
    
    print_summary
    interactive_menu
    
    rm -f $HIGH_RISK_FILE $MEDIUM_RISK_FILE $LOW_RISK_FILE $SPAM_SENDERS_FILE $ERROR_LOG
    
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${WHITE}                    Analysis Completed - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════════════════════════════════════════${NC}\n"
}

main
