#!/bin/bash

# =============================================================================
# JetBackup 5 Status Report Script - Complete Version with Telegram
# =============================================================================
# Description: Comprehensive backup monitoring script with HTML report and Telegram notification
# Version: 3.3 - Fixed grep -c multi-line output bug
# =============================================================================

# Prevent pipe failures from stopping the script
set +o pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
TELEGRAM_BOT_TOKEN="8770766348:AAEcXgiu12B6KSnRzgbwiRe2Ty3sRG8eExk"
TELEGRAM_CHAT_ID="992809735"
HTML_REPORT="/tmp/jetbackup_report_$(date +%Y%m%d_%H%M%S).html"
SERVER_NAME=$(hostname -f)
REPORT_DATE=$(date "+%Y-%m-%d %H:%M:%S %Z")

# =============================================================================
# COLOR DEFINITIONS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
RESET='\033[0m'

ICON_SUCCESS="✅"
ICON_WARNING="⚠️"
ICON_ERROR="❌"
ICON_INFO="ℹ️"
ICON_SERVER="🖥️"
ICON_BACKUP="💾"
ICON_CHART="📊"
ICON_SEARCH="🔍"
ICON_DATABASE="🗄️"
ICON_LOCK="🔒"
ICON_FTP="📁"
ICON_DISK="💿"

# Global variables for HTML report data
LOG_FILE=""
TOTAL_COMPLETED=0
TOTAL_PARTIAL=0
TOTAL_FAILED=0
TOTAL_ACCOUNTS=0
SUCCESS_RATE=0
MYSQL_ERRORS=0
EXPIRED_SSL=0
INVALID_FTP=0

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Safe grep count - fixes multi-line output bug
safe_grep_count() {
    local pattern="$1"
    local file="$2"
    local result
    
    result=$(timeout 5 grep -c "$pattern" "$file" 2>/dev/null | head -1) || result=0
    
    # Clean up - take only first number
    result=$(echo "$result" | grep -oP '^\d+' | head -1)
    
    # Validate
    if [[ "$result" =~ ^[0-9]+$ ]]; then
        echo "$result"
    else
        echo "0"
    fi
}

print_header() {
    local title="$1"
    local icon="$2"
    echo -e "\n${BG_BLUE}${WHITE}${BOLD}${icon} ${title}${RESET}"
}

print_subheader() {
    local title="$1"
    echo -e "\n${CYAN}${BOLD}▸ ${title}${RESET}"
    echo -e "${CYAN}$(printf '─%.0s' {1..70})${RESET}"
}

print_success() { echo -e "${GREEN}  ${ICON_SUCCESS} $1${RESET}"; }
print_warning() { echo -e "${YELLOW}  ${ICON_WARNING} $1${RESET}"; }
print_error() { echo -e "${RED}  ${ICON_ERROR} $1${RESET}"; }
print_info() { echo -e "${BLUE}  ${ICON_INFO} $1${RESET}"; }

format_duration() {
    local total_seconds=$1
    [ -z "$total_seconds" ] && total_seconds=0
    # Ensure integer
    total_seconds=$(echo "$total_seconds" | grep -oP '^\d+' | head -1)
    [ -z "$total_seconds" ] && total_seconds=0
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))
    printf "%02dh %02dm %02ds" $hours $minutes $seconds
}

format_timestamp() {
    local timestamp="$1"
    date -d "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp"
}

get_status_display() {
    local status_code=$1
    case $status_code in
        1) echo -e "${YELLOW}⏳ PENDING${RESET}" ;;
        2) echo -e "${BLUE}⚡ PROCESSING${RESET}" ;;
        3) echo -e "${GREEN}✅ COMPLETED${RESET}" ;;
        4) echo -e "${YELLOW}⚠️  PARTIAL${RESET}" ;;
        5) echo -e "${RED}❌ FAILED${RESET}" ;;
        6) echo -e "${MAGENTA}🛑 ABORTED${RESET}" ;;
        7) echo -e "${RED}💀 NEVER_FINISHED${RESET}" ;;
        *) echo -e "${GRAY}❓ UNKNOWN($status_code)${RESET}" ;;
    esac
}

get_status_html() {
    local status_code=$1
    case $status_code in
        1) echo "<span class='badge badge-pending'>⏳ PENDING</span>" ;;
        2) echo "<span class='badge badge-processing'>⚡ PROCESSING</span>" ;;
        3) echo "<span class='badge badge-completed'>✅ COMPLETED</span>" ;;
        4) echo "<span class='badge badge-partial'>⚠️ PARTIAL</span>" ;;
        5) echo "<span class='badge badge-failed'>❌ FAILED</span>" ;;
        6) echo "<span class='badge badge-aborted'>🛑 ABORTED</span>" ;;
        7) echo "<span class='badge badge-failed'>💀 NEVER_FINISHED</span>" ;;
        *) echo "<span class='badge badge-unknown'>❓ UNKNOWN($status_code)</span>" ;;
    esac
}

get_log_stats() {
    local log_file="$1"
    
    if [ -z "$log_file" ] || [ ! -f "$log_file" ]; then
        echo "0|0|0"
        return
    fi
    
    local completed=$(safe_grep_count 'Backup Completed' "$log_file")
    local partial=$(safe_grep_count 'Backup Partially Completed' "$log_file")
    local failed=$(safe_grep_count 'Backup Failed' "$log_file")
    
    echo "${completed}|${partial}|${failed}"
}

html_escape() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

# =============================================================================
# TELEGRAM FUNCTIONS
# =============================================================================

send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${message}" \
        -d parse_mode="HTML" \
        -d disable_web_page_preview="true" > /dev/null 2>&1
}

send_telegram_document() {
    local file_path="$1"
    local caption="$2"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TELEGRAM_CHAT_ID}" \
        -F document="@${file_path}" \
        -F caption="${caption}" \
        -F parse_mode="HTML" > /dev/null 2>&1
}

# =============================================================================
# HTML REPORT FUNCTIONS
# =============================================================================

write_html_report() {
    local daily_rows="$1"
    local weekly_rows="$2"
    local failed_html="$3"
    local partial_html="$4"
    local health_html="$5"
    local dest_html="$6"
    
    cat > "$HTML_REPORT" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>JetBackup 5 Status Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
        }
        
        .header .subtitle {
            font-size: 1.1em;
            opacity: 0.9;
        }
        
        .content {
            padding: 30px;
        }
        
        .section {
            margin-bottom: 30px;
            background: #f8f9fa;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.07);
        }
        
        .section-title {
            font-size: 1.8em;
            color: #1e3c72;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 3px solid #2a5298;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
            background: white;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        }
        
        th {
            background: #1e3c72;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        
        td {
            padding: 12px;
            border-bottom: 1px solid #e9ecef;
        }
        
        tr:hover {
            background: #f8f9fa;
        }
        
        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
        }
        
        .badge-completed { background: #d4edda; color: #155724; }
        .badge-pending { background: #fff3cd; color: #856404; }
        .badge-processing { background: #cce5ff; color: #004085; }
        .badge-partial { background: #fff3cd; color: #856404; }
        .badge-failed { background: #f8d7da; color: #721c24; }
        .badge-aborted { background: #e2e3e5; color: #383d41; }
        .badge-unknown { background: #e2e3e5; color: #6c757d; }
        
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            margin: 10px;
            text-align: center;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            flex: 1;
        }
        
        .stat-number {
            font-size: 2em;
            font-weight: bold;
            margin: 10px 0;
        }
        
        .stat-label {
            color: #6c757d;
            font-size: 0.9em;
        }
        
        .stats-container {
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
        }
        
        .error-item {
            background: white;
            padding: 15px;
            margin: 10px 0;
            border-radius: 8px;
            border-left: 4px solid #dc3545;
        }
        
        .warning-item {
            background: white;
            padding: 15px;
            margin: 10px 0;
            border-radius: 8px;
            border-left: 4px solid #ffc107;
        }
        
        .success-item {
            background: white;
            padding: 15px;
            margin: 10px 0;
            border-radius: 8px;
            border-left: 4px solid #28a745;
        }
        
        .info-item {
            background: white;
            padding: 15px;
            margin: 10px 0;
            border-radius: 8px;
            border-left: 4px solid #007bff;
        }
        
        .progress-bar {
            width: 100%;
            height: 30px;
            background: #e9ecef;
            border-radius: 15px;
            overflow: hidden;
            margin: 10px 0;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #28a745 0%, #20c997 100%);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            transition: width 0.3s ease;
        }
        
        .footer {
            text-align: center;
            padding: 20px;
            color: #6c757d;
            border-top: 1px solid #dee2e6;
            margin-top: 30px;
        }
        
        .account-detail {
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            background: #f8f9fa;
            padding: 10px;
            border-radius: 5px;
            margin: 5px 0;
            word-break: break-all;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 JetBackup 5 Status Report</h1>
            <div class="subtitle">Server: ${SERVER_NAME} | Date: ${REPORT_DATE}</div>
        </div>
        <div class="content">
            <div class="section">
                <div class="section-title">💾 Daily Backups (Last 20)</div>
                <table>
                    <thead>
                        <tr>
                            <th>Date</th>
                            <th>Status</th>
                            <th>Duration</th>
                            <th>Total Accounts</th>
                            <th>Success</th>
                            <th>Partial</th>
                            <th>Failed</th>
                            <th>Type</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${daily_rows}
                    </tbody>
                </table>
            </div>

            <div class="section">
                <div class="section-title">💾 Weekly Backups (Last 20)</div>
                <table>
                    <thead>
                        <tr>
                            <th>Date</th>
                            <th>Status</th>
                            <th>Duration</th>
                            <th>Total Accounts</th>
                            <th>Success</th>
                            <th>Partial</th>
                            <th>Failed</th>
                            <th>Type</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${weekly_rows}
                    </tbody>
                </table>
            </div>

            <div class="section">
                <div class="section-title">📊 Latest Weekly Backup Analysis</div>
                <p style="margin-bottom: 15px;"><strong>Log File:</strong> <code>${LOG_FILE}</code></p>
                <div class="stats-container">
                    <div class="stat-card" style="border-top: 4px solid #007bff;">
                        <div class="stat-label">Total Accounts</div>
                        <div class="stat-number" style="color: #007bff;">${TOTAL_ACCOUNTS}</div>
                    </div>
                    <div class="stat-card" style="border-top: 4px solid #28a745;">
                        <div class="stat-label">Completed</div>
                        <div class="stat-number" style="color: #28a745;">${TOTAL_COMPLETED}</div>
                        <div class="stat-label">($(( TOTAL_COMPLETED * 100 / (TOTAL_ACCOUNTS > 0 ? TOTAL_ACCOUNTS : 1) ))%)</div>
                    </div>
                    <div class="stat-card" style="border-top: 4px solid #ffc107;">
                        <div class="stat-label">Partial</div>
                        <div class="stat-number" style="color: #ffc107;">${TOTAL_PARTIAL}</div>
                        <div class="stat-label">($(( TOTAL_PARTIAL * 100 / (TOTAL_ACCOUNTS > 0 ? TOTAL_ACCOUNTS : 1) ))%)</div>
                    </div>
                    <div class="stat-card" style="border-top: 4px solid #dc3545;">
                        <div class="stat-label">Failed</div>
                        <div class="stat-number" style="color: #dc3545;">${TOTAL_FAILED}</div>
                        <div class="stat-label">($(( TOTAL_FAILED * 100 / (TOTAL_ACCOUNTS > 0 ? TOTAL_ACCOUNTS : 1) ))%)</div>
                    </div>
                </div>
                <div style="margin-top: 20px;">
                    <div style="display: flex; justify-content: space-between; margin-bottom: 5px;">
                        <span>Success Rate</span>
                        <span><strong>${SUCCESS_RATE}%</strong></span>
                    </div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${SUCCESS_RATE}%;">${SUCCESS_RATE}%</div>
                    </div>
                </div>
            </div>

            <div class="section">
                <div class="section-title">❌ Failed Accounts & Error Details</div>
                ${failed_html}
            </div>

            <div class="section">
                <div class="section-title">⚠️ Partial Accounts & Issues</div>
                ${partial_html}
            </div>

            <div class="section">
                <div class="section-title">🏥 System Health Summary</div>
                ${health_html}
            </div>

            <div class="section">
                <div class="section-title">⚠️ Destination & Service Issues (Last 7 Days)</div>
                ${dest_html}
            </div>
        </div>
        <div class="footer">
            <p>🚀 Generated by Ultahost Server Activities Bot</p>
            <p>Report Date: ${REPORT_DATE}</p>
        </div>
    </div>
</body>
</html>
EOF
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

clear

cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║              JETBACKUP 5 - BACKUP STATUS REPORT                 ║
╚══════════════════════════════════════════════════════════════════╝
EOF

# Server Information
print_header "SERVER INFORMATION" "${ICON_SERVER}"
echo -e "${WHITE}${BOLD}  Hostname:${RESET} ${GREEN}${SERVER_NAME}${RESET}"
echo -e "${WHITE}${BOLD}  Date:${RESET}     ${GRAY}${REPORT_DATE}${RESET}"

# Fetch backup data
print_info "Fetching backup data..."
BACKUP_DATA=$(timeout 10 jetbackup5api -F listLogs -D "find[type]=1&sort[start_time]=-1&limit=20" -O json 2>/dev/null)

if [ -z "$BACKUP_DATA" ]; then
    print_error "Failed to fetch backup data"
    exit 1
fi

LOG_COUNT=$(echo "$BACKUP_DATA" | jq -r '.data.logs | length' 2>/dev/null || echo "0")
print_success "Found $LOG_COUNT backup logs"
echo ""

# =============================================================================
# DAILY BACKUPS
# =============================================================================
print_header "DAILY BACKUPS (Last 20)" "${ICON_BACKUP}"

DAILY_HTML_ROWS=""

while IFS=$'\t' read -r start_time duration status accounts backup_type log_file; do
    if [ -n "$start_time" ]; then
        FORMATTED_TIME=$(format_timestamp "$start_time")
        FORMATTED_DUR=$(format_duration ${duration:-0})
        STATUS_HTML=$(get_status_html $status)
        
        printf "${WHITE}${BOLD}  %-20s${RESET} " "$FORMATTED_TIME"
        echo -e "| Status: $(get_status_display $status) | Duration: ${CYAN}${FORMATTED_DUR}${RESET} | Accounts: ${GREEN}${accounts:-N/A}${RESET}"
        echo -e "  ${DIM}Type: ${backup_type}${RESET}"
        
        if [ -n "$log_file" ] && [ -f "$log_file" ]; then
            STATS=$(get_log_stats "$log_file")
            IFS='|' read -r completed partial failed <<< "$STATS"
            
            echo -ne "  ${DIM}Details:${RESET} "
            echo -ne "${GREEN}✓ ${completed} completed${RESET}  "
            echo -ne "${YELLOW}⚠ ${partial} partial${RESET}  "
            echo -e "${RED}✗ ${failed} failed${RESET}"
            
            ESCAPED_TYPE=$(html_escape "$backup_type")
            DAILY_HTML_ROWS+="<tr><td>${FORMATTED_TIME}</td><td>${STATUS_HTML}</td><td>${FORMATTED_DUR}</td><td>${accounts:-N/A}</td><td style='color: #28a745; font-weight: bold;'>${completed}</td><td style='color: #ffc107; font-weight: bold;'>${partial}</td><td style='color: #dc3545; font-weight: bold;'>${failed}</td><td style='font-size: 0.9em; color: #6c757d;'>${ESCAPED_TYPE}</td></tr>"
        else
            echo -e "  ${DIM}Log file not accessible${RESET}"
            ESCAPED_TYPE=$(html_escape "$backup_type")
            DAILY_HTML_ROWS+="<tr><td>${FORMATTED_TIME}</td><td>${STATUS_HTML}</td><td>${FORMATTED_DUR}</td><td>${accounts:-N/A}</td><td colspan='3' style='color: #6c757d;'>Log not accessible</td><td style='font-size: 0.9em; color: #6c757d;'>${ESCAPED_TYPE}</td></tr>"
        fi
        
        echo -e "  ${GRAY}─────────────────────────────────────────────────────────────${RESET}"
    fi
done < <(echo "$BACKUP_DATA" | timeout 5 jq -r '.data.logs[] | select(.info.Backup | test("Daily"; "i")) | [.start_time, .execution_time, .status, (.info["Total Accounts"] // "N/A"), .info.Backup, .file] | @tsv' 2>/dev/null | head -10)

# =============================================================================
# WEEKLY BACKUPS
# =============================================================================
print_header "WEEKLY BACKUPS (Last 20)" "${ICON_BACKUP}"

WEEKLY_HTML_ROWS=""

while IFS=$'\t' read -r start_time duration status accounts backup_type log_file; do
    if [ -n "$start_time" ]; then
        FORMATTED_TIME=$(format_timestamp "$start_time")
        FORMATTED_DUR=$(format_duration ${duration:-0})
        STATUS_HTML=$(get_status_html $status)
        
        printf "${WHITE}${BOLD}  %-20s${RESET} " "$FORMATTED_TIME"
        echo -e "| Status: $(get_status_display $status) | Duration: ${CYAN}${FORMATTED_DUR}${RESET} | Accounts: ${GREEN}${accounts:-N/A}${RESET}"
        echo -e "  ${DIM}Type: ${backup_type}${RESET}"
        
        if [ -n "$log_file" ] && [ -f "$log_file" ]; then
            STATS=$(get_log_stats "$log_file")
            IFS='|' read -r completed partial failed <<< "$STATS"
            
            echo -ne "  ${DIM}Details:${RESET} "
            echo -ne "${GREEN}✓ ${completed} completed${RESET}  "
            echo -ne "${YELLOW}⚠ ${partial} partial${RESET}  "
            echo -e "${RED}✗ ${failed} failed${RESET}"
            
            ESCAPED_TYPE=$(html_escape "$backup_type")
            WEEKLY_HTML_ROWS+="<tr><td>${FORMATTED_TIME}</td><td>${STATUS_HTML}</td><td>${FORMATTED_DUR}</td><td>${accounts:-N/A}</td><td style='color: #28a745; font-weight: bold;'>${completed}</td><td style='color: #ffc107; font-weight: bold;'>${partial}</td><td style='color: #dc3545; font-weight: bold;'>${failed}</td><td style='font-size: 0.9em; color: #6c757d;'>${ESCAPED_TYPE}</td></tr>"
        else
            echo -e "  ${DIM}Log file not accessible${RESET}"
            ESCAPED_TYPE=$(html_escape "$backup_type")
            WEEKLY_HTML_ROWS+="<tr><td>${FORMATTED_TIME}</td><td>${STATUS_HTML}</td><td>${FORMATTED_DUR}</td><td>${accounts:-N/A}</td><td colspan='3' style='color: #6c757d;'>Log not accessible</td><td style='font-size: 0.9em; color: #6c757d;'>${ESCAPED_TYPE}</td></tr>"
        fi
        
        echo -e "  ${GRAY}─────────────────────────────────────────────────────────────${RESET}"
    fi
done < <(echo "$BACKUP_DATA" | timeout 5 jq -r '.data.logs[] | select(.info.Backup | test("Weekly"; "i")) | [.start_time, .execution_time, .status, (.info["Total Accounts"] // "N/A"), .info.Backup, .file] | @tsv' 2>/dev/null | head -10)

# =============================================================================
# LATEST WEEKLY BACKUP DETAIL
# =============================================================================
print_header "LATEST WEEKLY BACKUP ANALYSIS" "${ICON_CHART}"

LOG_FILE=$(timeout 10 jetbackup5api -F listLogs \
    -D "find[type]=1&find[info.Backup]=Weekly Compressed Backup&sort[start_time]=-1&limit=1" \
    -O json 2>/dev/null | jq -r '.data.logs[0].file // empty')

if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
    print_error "No weekly backup log found"
    print_info "Searching for any available log..."
    LOG_FILE=$(echo "$BACKUP_DATA" | jq -r '.data.logs[0].file // empty' 2>/dev/null)
    [ -n "$LOG_FILE" ] && print_info "Using: ${LOG_FILE}" || { print_error "No logs available"; exit 1; }
fi

print_info "Log File: ${UNDERLINE}${LOG_FILE}${RESET}"

# Backup statistics - using safe_grep_count
TOTAL_COMPLETED=$(safe_grep_count 'Backup Completed' "$LOG_FILE")
TOTAL_PARTIAL=$(safe_grep_count 'Backup Partially Completed' "$LOG_FILE")
TOTAL_FAILED=$(safe_grep_count 'Backup Failed' "$LOG_FILE")
TOTAL_ACCOUNTS=$((TOTAL_COMPLETED + TOTAL_PARTIAL + TOTAL_FAILED))

print_subheader "Backup Statistics"
echo -e "${WHITE}  Total Accounts:   ${BOLD}${TOTAL_ACCOUNTS}${RESET}"
if [ "$TOTAL_ACCOUNTS" -gt 0 ]; then
    echo -e "${GREEN}  Completed:        ${BOLD}${TOTAL_COMPLETED}${RESET} ($(( TOTAL_COMPLETED * 100 / TOTAL_ACCOUNTS ))%)"
    echo -e "${YELLOW}  Partial:          ${BOLD}${TOTAL_PARTIAL}${RESET} ($(( TOTAL_PARTIAL * 100 / TOTAL_ACCOUNTS ))%)"
    echo -e "${RED}  Failed:           ${BOLD}${TOTAL_FAILED}${RESET} ($(( TOTAL_FAILED * 100 / TOTAL_ACCOUNTS ))%)"
else
    echo -e "${GREEN}  Completed:        ${BOLD}${TOTAL_COMPLETED}${RESET}"
    echo -e "${YELLOW}  Partial:          ${BOLD}${TOTAL_PARTIAL}${RESET}"
    echo -e "${RED}  Failed:           ${BOLD}${TOTAL_FAILED}${RESET}"
fi

if [ "$TOTAL_ACCOUNTS" -gt 0 ]; then
    SUCCESS_RATE=$(( TOTAL_COMPLETED * 100 / TOTAL_ACCOUNTS ))
    echo -ne "\n  ${BOLD}Success Rate: ${RESET}"
    if [ "$SUCCESS_RATE" -ge 90 ]; then
        echo -ne "${BG_GREEN}${WHITE}"
    elif [ "$SUCCESS_RATE" -ge 70 ]; then
        echo -ne "${BG_YELLOW}"
    else
        echo -ne "${BG_RED}${WHITE}"
    fi
    printf " %d%% " "$SUCCESS_RATE"
    echo -e "${RESET}"
else
    SUCCESS_RATE=0
fi

# =============================================================================
# FAILED ACCOUNTS - ENHANCED WITH FULL ERROR DETAILS
# =============================================================================
print_subheader "Failed Accounts & Error Details"

FAILED_PIDS=$(timeout 5 grep -B 2 'Backup Failed' "$LOG_FILE" 2>/dev/null | grep -oP 'PID \K[0-9]+' | sort -u || true)

FAILED_HTML=""

if [ -n "$FAILED_PIDS" ]; then
    FAILED_COUNT=$(echo "$FAILED_PIDS" | wc -l)
    CURRENT=0
    
    while IFS= read -r pid; do
        CURRENT=$((CURRENT + 1))
        
        ACCOUNT_NAME=$(timeout 3 grep "Transferring account" "$LOG_FILE" 2>/dev/null | grep "$pid" | grep -oP 'account "\K[^"]+' | head -1 || echo "")
        
        if [ -z "$ACCOUNT_NAME" ]; then
            ACCOUNT_NAME=$(timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | grep -oP 'account \K\S+(?= not found)' | head -1 || echo "Unknown")
        fi
        
        [ -z "$ACCOUNT_NAME" ] && ACCOUNT_NAME="Unknown"
        
        echo -e "\n${RED}${BOLD}  ❌ ${ACCOUNT_NAME}${RESET} ${DIM}(PID: ${pid})${RESET}"
        
        FAILED_HTML+="<div class='error-item'><h4 style='color: #dc3545;'>❌ $(html_escape "$ACCOUNT_NAME") <small style='color: #6c757d;'>(PID: ${pid})</small></h4><div class='account-detail'>"
        
        # Show ALL error lines for this PID (terminal output)
        echo -e "     ${DIM}${UNDERLINE}All Errors:${RESET}"
        timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | grep -E '\[ERROR\]|Backup Failed' | while IFS= read -r error_line; do
            if [ -n "$error_line" ]; then
                if echo "$error_line" | grep -q 'Backup Failed'; then
                    echo -e "     ${RED}▸ $(echo "$error_line" | grep -oP 'Backup Failed.*$' | head -c 250)${RESET}"
                else
                    echo -e "     ${RED}▸ $(echo "$error_line" | sed 's/.*\[ERROR\] */[ERROR] /' | head -c 250)${RESET}"
                fi
            fi
        done
        
        # Show WARNING lines too
        WARNINGS_EXIST=$(timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | grep -c '\[WARNING\]' 2>/dev/null | head -1) || WARNINGS_EXIST=0
        [[ "$WARNINGS_EXIST" =~ ^[0-9]+$ ]] || WARNINGS_EXIST=0
        if [ "$WARNINGS_EXIST" -gt 0 ]; then
            echo -e "     ${DIM}${UNDERLINE}Warnings:${RESET}"
            timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | grep '\[WARNING\]' | while IFS= read -r warning_line; do
                if [ -n "$warning_line" ]; then
                    echo -e "     ${YELLOW}▸ $(echo "$warning_line" | sed 's/.*\[WARNING\] */[WARNING] /' | head -c 250)${RESET}"
                fi
            done
        fi
        
        # HTML content - show all errors and warnings (up to 15 lines)
        while IFS= read -r error_line; do
            if [ -n "$error_line" ]; then
                CLEAN_ERROR=$(echo "$error_line" | sed 's/</\&lt;/g; s/>/\&gt;/g')
                FAILED_HTML+="${CLEAN_ERROR}<br>"
            fi
        done < <(timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | grep -E '\[ERROR\]|Backup Failed|\[WARNING\]' | head -15)
        
        FAILED_HTML+="</div></div>"
        
        echo -ne "${DIM}  [${CURRENT}/${FAILED_COUNT}]${RESET}\r"
        
    done <<< "$FAILED_PIDS"
    echo ""
else
    NOT_FOUND=$(timeout 5 grep -oP 'account \K\S+(?= not found)' "$LOG_FILE" 2>/dev/null | sort -u || true)
    if [ -n "$NOT_FOUND" ]; then
        while IFS= read -r account; do
            [ -z "$account" ] && continue
            echo -e "\n${RED}${BOLD}  ❌ ${account}${RESET}"
            echo -e "     ${DIM}Reason: Account not found on server${RESET}"
            
            FAILED_HTML+="<div class='error-item'><h4 style='color: #dc3545;'>❌ $(html_escape "$account")</h4><p style='color: #6c757d;'>Reason: Account not found on server</p>"
            
            echo -e "     ${DIM}${UNDERLINE}Related Errors:${RESET}"
            timeout 3 grep -B 3 -A 3 "account $account not found" "$LOG_FILE" 2>/dev/null | \
                grep -E '\[ERROR\]|\[WARNING\]' | head -5 | while IFS= read -r line; do
                if echo "$line" | grep -q '\[ERROR\]'; then
                    echo -e "     ${RED}▸ $(echo "$line" | sed 's/.*\[ERROR\] */[ERROR] /' | head -c 250)${RESET}"
                else
                    echo -e "     ${YELLOW}▸ $(echo "$line" | sed 's/.*\[WARNING\] */[WARNING] /' | head -c 250)${RESET}"
                fi
                CLEAN_LINE=$(echo "$line" | sed 's/</\&lt;/g; s/>/\&gt;/g')
                FAILED_HTML+="<br>${CLEAN_LINE}"
            done
            
            FAILED_HTML+="</div>"
        done <<< "$NOT_FOUND"
    else
        print_success "No failed accounts found"
        FAILED_HTML="<div class='success-item'>✅ No failed accounts found</div>"
    fi
fi

# =============================================================================
# PARTIAL ACCOUNTS
# =============================================================================
print_subheader "Partial Accounts & Issues"

PARTIAL_PIDS=$(timeout 5 grep 'Backup Partially Completed' "$LOG_FILE" 2>/dev/null | grep -oP 'PID \K[0-9]+' | sort -u || true)

PARTIAL_HTML=""

if [ -n "$PARTIAL_PIDS" ]; then
    PARTIAL_COUNT=$(echo "$PARTIAL_PIDS" | wc -l)
    CURRENT=0
    
    while IFS= read -r pid; do
        CURRENT=$((CURRENT + 1))
        
        ACCOUNT_NAME=$(timeout 3 grep "Transferring account" "$LOG_FILE" 2>/dev/null | grep "$pid" | grep -oP 'account "\K[^"]+' | head -1 || echo "Unknown")
        
        ERROR_COUNT=$(timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | grep -c '\[ERROR\]' 2>/dev/null | head -1) || ERROR_COUNT=0
        WARNING_COUNT=$(timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | grep -c '\[WARNING\]' 2>/dev/null | head -1) || WARNING_COUNT=0
        
        [[ "$ERROR_COUNT" =~ ^[0-9]+$ ]] || ERROR_COUNT=0
        [[ "$WARNING_COUNT" =~ ^[0-9]+$ ]] || WARNING_COUNT=0
        
        echo -e "\n${YELLOW}${BOLD}  ⚠️  ${ACCOUNT_NAME}${RESET}${YELLOW} (PID: ${pid})${RESET}"
        echo -e "     ${RED}Errors: ${ERROR_COUNT}${RESET} | ${YELLOW}Warnings: ${WARNING_COUNT}${RESET}"
        
        PARTIAL_HTML+="<div class='warning-item'><h4 style='color: #856404;'>⚠️ $(html_escape "$ACCOUNT_NAME") <small>(PID: ${pid})</small></h4><p><span style='color: #dc3545;'>Errors: ${ERROR_COUNT}</span> | <span style='color: #856404;'>Warnings: ${WARNING_COUNT}</span></p><div class='account-detail'>"
        
        while IFS= read -r error_line; do
            if [ -n "$error_line" ]; then
                CLEAN_ERROR=$(echo "$error_line" | sed 's/</\&lt;/g; s/>/\&gt;/g')
                PARTIAL_HTML+="${CLEAN_ERROR}<br>"
            fi
        done < <(timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | grep -E '\[ERROR\]|\[WARNING\]' | head -5)
        
        PARTIAL_HTML+="</div></div>"
        
        timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | \
            grep -E '\[ERROR\]' | head -3 | while IFS= read -r line; do
            echo -e "     ${RED}▸ $(echo "$line" | sed 's/.*\[ERROR\] */[ERROR] /' | head -c 250)${RESET}"
        done
        
        timeout 3 grep "$pid" "$LOG_FILE" 2>/dev/null | \
            grep -E '\[WARNING\]' | head -2 | while IFS= read -r line; do
            echo -e "     ${YELLOW}▸ $(echo "$line" | sed 's/.*\[WARNING\] */[WARNING] /' | head -c 250)${RESET}"
        done
        
        TOTAL_ISSUES=$((ERROR_COUNT + WARNING_COUNT))
        if [ "$TOTAL_ISSUES" -gt 5 ]; then
            echo -e "     ${DIM}... showing 5 of ${TOTAL_ISSUES} issues${RESET}"
        fi
        
        echo -ne "${DIM}  [${CURRENT}/${PARTIAL_COUNT}]${RESET}\r"
    done <<< "$PARTIAL_PIDS"
    echo ""
else
    print_success "No partial accounts found"
    PARTIAL_HTML="<div class='success-item'>✅ No partial accounts found</div>"
fi

# =============================================================================
# SYSTEM HEALTH SUMMARY
# =============================================================================
print_subheader "System Health Summary"

echo ""

HEALTH_HTML=""

# MySQL Errors
MYSQL_ERRORS=$(safe_grep_count 'Failed export\|marked as crashed\|Server has gone away' "$LOG_FILE")

if [ "$MYSQL_ERRORS" -gt 0 ]; then
    print_warning "${ICON_DATABASE} MySQL Errors: ${RED}${MYSQL_ERRORS}${RESET}"
    HEALTH_HTML+="<div class='warning-item'><h4>🗄️ MySQL Errors: ${MYSQL_ERRORS}</h4>"
    
    timeout 5 grep -E 'Failed export|marked as crashed|Server has gone away' "$LOG_FILE" 2>/dev/null | head -3 | while IFS= read -r line; do
        if echo "$line" | grep -q 'Failed export'; then
            DB_NAME=$(echo "$line" | grep -oP "database \K[\"'][^\"']+[\"']" | tr -d '"'"'" || echo "unknown")
            echo -e "     ${RED}▸ Database: ${DB_NAME}${RESET}"
            HEALTH_HTML+="<p style='color: #dc3545;'>▸ Database: $(html_escape "$DB_NAME")</p>"
        fi
    done
    HEALTH_HTML+="</div>"
else
    print_success "${ICON_DATABASE} MySQL Errors: 0"
    HEALTH_HTML+="<div class='success-item'><h4>🗄️ MySQL Errors: 0</h4></div>"
fi

# Expired SSL
EXPIRED_SSL=$(safe_grep_count 'already expired' "$LOG_FILE")

if [ "$EXPIRED_SSL" -gt 0 ]; then
    print_warning "${ICON_LOCK} Expired SSL: ${RED}${EXPIRED_SSL}${RESET}"
    HEALTH_HTML+="<div class='warning-item'><h4>🔒 Expired SSL Certificates: ${EXPIRED_SSL}</h4>"
    
    timeout 5 grep 'already expired' "$LOG_FILE" 2>/dev/null | head -3 | while IFS= read -r line; do
        DOMAIN=$(echo "$line" | grep -oP '(?<=domain |for |: )[\w.-]+\.[a-z]{2,}' | head -1 || echo "unknown")
        echo -e "     ${RED}▸ Domain: ${DOMAIN}${RESET}"
        HEALTH_HTML+="<p style='color: #dc3545;'>▸ Domain: $(html_escape "$DOMAIN")</p>"
    done
    HEALTH_HTML+="</div>"
else
    print_success "${ICON_LOCK} Expired SSL: 0"
    HEALTH_HTML+="<div class='success-item'><h4>🔒 Expired SSL Certificates: 0</h4></div>"
fi

# Invalid FTP
INVALID_FTP=$(safe_grep_count 'Invalid FTP account' "$LOG_FILE")

if [ "$INVALID_FTP" -gt 0 ]; then
    print_warning "${ICON_FTP} Invalid FTP: ${RED}${INVALID_FTP}${RESET}"
    HEALTH_HTML+="<div class='warning-item'><h4>📁 Invalid FTP Accounts: ${INVALID_FTP}</h4>"
    
    timeout 5 grep 'Invalid FTP account' "$LOG_FILE" 2>/dev/null | head -3 | while IFS= read -r line; do
        FTP_USER=$(echo "$line" | grep -oP 'Invalid FTP account[^.]*\.' | head -c 130 || echo "$line" | head -c 130)
        echo -e "     ${RED}▸ ${FTP_USER}${RESET}"
        HEALTH_HTML+="<p style='color: #dc3545;'>▸ $(html_escape "$FTP_USER")</p>"
    done
    HEALTH_HTML+="</div>"
else
    print_success "${ICON_FTP} Invalid FTP: 0"
    HEALTH_HTML+="<div class='success-item'><h4>📁 Invalid FTP Accounts: 0</h4></div>"
fi

# Disk Usage
DISK_USAGE=$(timeout 10 grep -oP 'Disk Space Usage is \K[0-9.]+\%' "$LOG_FILE" 2>/dev/null | tail -1 || echo "N/A")
echo -e "${WHITE}  ${ICON_DISK} Disk Usage: ${BOLD}${DISK_USAGE}${RESET}"

HEALTH_HTML+="<div class='info-item'><h4>💿 Disk Usage: ${DISK_USAGE}</h4>"

DISK_NUM=$(echo "$DISK_USAGE" | sed 's/%//')
if [ -n "$DISK_NUM" ] && [ "$DISK_NUM" != "N/A" ] && [[ "$DISK_NUM" =~ ^[0-9.]+$ ]]; then
    if (( $(echo "$DISK_NUM > 90" | bc -l 2>/dev/null) )); then
        print_error "CRITICAL: Disk usage above 90%!"
        HEALTH_HTML+="<p style='color: #dc3545; font-weight: bold;'>⚠️ CRITICAL: Disk usage above 90%!</p>"
    elif (( $(echo "$DISK_NUM > 80" | bc -l 2>/dev/null) )); then
        print_warning "WARNING: Disk usage above 80%"
        HEALTH_HTML+="<p style='color: #856404;'>⚠️ WARNING: Disk usage above 80%</p>"
    fi
fi
HEALTH_HTML+="</div>"

# =============================================================================
# DESTINATION ISSUES
# =============================================================================
print_header "DESTINATION & SERVICE ISSUES (Last 7 Days)" "${ICON_WARNING}"

DEST_HTML=""

if systemctl is-active --quiet jetbackup5d 2>/dev/null; then
    print_success "JetBackup Service: ${GREEN}Active${RESET}"
    DEST_HTML+="<div class='success-item'>✅ JetBackup Service: Active</div>"
    
    ISSUES=$(timeout 5 journalctl -u jetbackup5d --since "7 days ago" --no-pager 2>/dev/null | \
        grep -E '\[Error\]|\[Warning\]' | \
        grep -vi 'snapshot cleanup\|integrity check\|cleanup.*completed' | \
        tail -10 || true)
    
    if [ -n "$ISSUES" ]; then
        echo "$ISSUES" | while IFS= read -r line; do
            if echo "$line" | grep -q '\[Error\]'; then
                echo -e "  ${RED}$(echo "$line" | cut -c1-120)${RESET}"
            else
                echo -e "  ${YELLOW}$(echo "$line" | cut -c1-120)${RESET}"
            fi
        done
    else
        print_success "No destination or service issues found"
    fi
else
    print_error "JetBackup Service: ${RED}Inactive or Not Found${RESET}"
    DEST_HTML+="<div class='error-item'>❌ JetBackup Service: Inactive or Not Found</div>"
fi

# =============================================================================
# WRITE HTML REPORT
# =============================================================================
write_html_report "$DAILY_HTML_ROWS" "$WEEKLY_HTML_ROWS" "$FAILED_HTML" "$PARTIAL_HTML" "$HEALTH_HTML" "$DEST_HTML"

# =============================================================================
# QUICK COMMANDS
# =============================================================================
print_header "QUICK COMMANDS" "${ICON_INFO}"
echo -e "${GRAY}  View full log:         ${WHITE}less ${LOG_FILE}${RESET}"
echo -e "${GRAY}  Search all errors:     ${WHITE}grep -E '\[ERROR\]|Backup Failed' ${LOG_FILE} | less${RESET}"
echo -e "${GRAY}  Service status:        ${WHITE}systemctl status jetbackup5d${RESET}"
echo -e "${GRAY}  HTML Report:           ${WHITE}${HTML_REPORT}${RESET}"

echo -e "\n${BG_BLUE}${WHITE}${BOLD} Report Generated: $(date "+%Y-%m-%d %H:%M:%S") ${RESET}\n"

# =============================================================================
# SEND TELEGRAM NOTIFICATION
# =============================================================================
echo -e "${CYAN}${BOLD}Sending Telegram notification...${RESET}"

# Create Telegram message
TELEGRAM_MESSAGE="🚀 <b>JetBackup 5 Status Report</b>

🖥 <b>Server:</b> ${SERVER_NAME}
📅 <b>Date:</b> ${REPORT_DATE}

━━━━━━━━━━━━━━━━━━━━━━

📊 <b>Latest Backup Summary:</b>
▪ Total Accounts: <b>${TOTAL_ACCOUNTS}</b>"

if [ "$TOTAL_ACCOUNTS" -gt 0 ]; then
    TELEGRAM_MESSAGE+="
▪ ✅ Completed: <b>${TOTAL_COMPLETED}</b> ($(( TOTAL_COMPLETED * 100 / TOTAL_ACCOUNTS ))%)
▪ ⚠️ Partial: <b>${TOTAL_PARTIAL}</b> ($(( TOTAL_PARTIAL * 100 / TOTAL_ACCOUNTS ))%)
▪ ❌ Failed: <b>${TOTAL_FAILED}</b> ($(( TOTAL_FAILED * 100 / TOTAL_ACCOUNTS ))%)"
fi

TELEGRAM_MESSAGE+="

━━━━━━━━━━━━━━━━━━━━━━

📈 <b>Success Rate:</b> ${SUCCESS_RATE}%"

if [ "$TOTAL_FAILED" -gt 0 ]; then
    TELEGRAM_MESSAGE+="

⚠️ <b>Failed Accounts Detected:</b> ${TOTAL_FAILED} accounts"
fi

if [ "$MYSQL_ERRORS" -gt 0 ] || [ "$EXPIRED_SSL" -gt 0 ] || [ "$INVALID_FTP" -gt 0 ]; then
    TELEGRAM_MESSAGE+="

🔍 <b>Issues Found:</b>"
    [ "$MYSQL_ERRORS" -gt 0 ] && TELEGRAM_MESSAGE+="
▪ MySQL Errors: ${MYSQL_ERRORS}"
    [ "$EXPIRED_SSL" -gt 0 ] && TELEGRAM_MESSAGE+="
▪ Expired SSL: ${EXPIRED_SSL}"
    [ "$INVALID_FTP" -gt 0 ] && TELEGRAM_MESSAGE+="
▪ Invalid FTP: ${INVALID_FTP}"
fi

TELEGRAM_MESSAGE+="

🔗 <b>Full HTML Report:</b> Attached below"

# Send message
send_telegram_message "$TELEGRAM_MESSAGE"

# Send HTML file
REPORT_FILENAME="JetBackup_Report_$(date +%Y%m%d_%H%M%S).html"
cp "$HTML_REPORT" "/tmp/${REPORT_FILENAME}"
send_telegram_document "/tmp/${REPORT_FILENAME}" "📄 JetBackup 5 Detailed Report - ${SERVER_NAME} - ${REPORT_DATE}"

# Cleanup
rm -f "/tmp/${REPORT_FILENAME}" 2>/dev/null

echo -e "${GREEN}${BOLD}✅ Report sent to Telegram successfully!${RESET}"
echo -e "${GREEN}${BOLD}📄 HTML Report saved: ${HTML_REPORT}${RESET}"
echo ""

exit 0
