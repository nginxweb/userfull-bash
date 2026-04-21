#!/bin/bash

# ======================================================================
# ╔══════════════════════════════════════════════════════════════════╗
# ║     EXIM QUEUE SPAM ANALYZER - TELEGRAM ALERT SYSTEM            ║
# ║              CRON JOB COMPATIBLE VERSION                         ║
# ╚══════════════════════════════════════════════════════════════════╝
# ======================================================================

# Set full PATH for cron environment (based on your server's PATH)
export PATH="/usr/local/cpanel/3rdparty/lib/path-bin:/usr/share/Modules/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin"

# Telegram Configuration
CHAT_ID="992809735"
BOT_TOKEN="8770766348:AAEcXgiu12B6KSnRzgbwiRe2Ty3sRG8eExk"

# Temporary files (use /tmp which is writable in cron)
TEMP_DIR="/tmp/exim_telegram_$$"
mkdir -p "$TEMP_DIR" || {
    echo "Failed to create temp directory"
    exit 1
}

QUEUE_DETAIL="$TEMP_DIR/queue_detail.txt"
SENDER_LIST="$TEMP_DIR/senders.txt"
DOMAIN_LIST="$TEMP_DIR/domains.txt"
CPANEL_LIST="$TEMP_DIR/cpanel.txt"
CWD_LIST="$TEMP_DIR/cwd.txt"
HOURLY_STATS="$TEMP_DIR/hourly.txt"
CRON_USERS="$TEMP_DIR/cron_users.txt"
HIGH_RISK="$TEMP_DIR/high_risk.txt"
REPORT_FILE="$TEMP_DIR/report.txt"
ERROR_LOG="$TEMP_DIR/error.log"

# Redirect all errors to log file
exec 2>>"$ERROR_LOG"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "$(date): Error - Script must be run as root" >> "$ERROR_LOG"
    exit 1
fi

# Find full paths for required commands (fallback to standard paths)
EXIM_CMD=$(which exim 2>/dev/null || echo "/usr/sbin/exim")
CURL_CMD=$(which curl 2>/dev/null || echo "/usr/bin/curl")
GREP_CMD=$(which grep 2>/dev/null || echo "/bin/grep")
AWK_CMD=$(which awk 2>/dev/null || echo "/usr/bin/awk")
SED_CMD=$(which sed 2>/dev/null || echo "/bin/sed")
SORT_CMD=$(which sort 2>/dev/null || echo "/usr/bin/sort")
UNIQ_CMD=$(which uniq 2>/dev/null || echo "/usr/bin/uniq")
HEAD_CMD=$(which head 2>/dev/null || echo "/usr/bin/head")
CUT_CMD=$(which cut 2>/dev/null || echo "/usr/bin/cut")
WC_CMD=$(which wc 2>/dev/null || echo "/usr/bin/wc")
DATE_CMD=$(which date 2>/dev/null || echo "/bin/date")

# Function to send message to Telegram
send_telegram() {
    local message="$1"
    
    # Create temporary file for message
    MSG_FILE="$TEMP_DIR/telegram_msg.txt"
    echo "$message" > "$MSG_FILE"
    
    # Send using curl with timeout
    RESPONSE=$($CURL_CMD --max-time 30 -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text@$MSG_FILE" \
        -d "parse_mode=HTML" 2>&1)
    
    if echo "$RESPONSE" | $GREP_CMD -q '"ok":true'; then
        echo "$($DATE_CMD): Message sent to Telegram successfully" >> "$ERROR_LOG"
        return 0
    else
        echo "$($DATE_CMD): Failed to send message. Response: $RESPONSE" >> "$ERROR_LOG"
        return 1
    fi
}

# Function to get today's date in log format
get_today_date() {
    $DATE_CMD +"%Y-%m-%d"
}

# Function to format large numbers
format_number() {
    local num=$1
    if [ "$num" -gt 1000 ]; then
        echo "$(($num / 1000))K"
    else
        echo "$num"
    fi
}

# 1. Check total emails in queue
QUEUE_COUNT=$($EXIM_CMD -bpc 2>>"$ERROR_LOG")
if [ -z "$QUEUE_COUNT" ]; then
    echo "$($DATE_CMD): Error executing exim -bpc command" >> "$ERROR_LOG"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "$($DATE_CMD): Total emails in queue: $QUEUE_COUNT" >> "$ERROR_LOG"

# Stop if queue count is below threshold
if [ "$QUEUE_COUNT" -le 100 ]; then
    echo "$($DATE_CMD): Queue count is below 100. No alert needed." >> "$ERROR_LOG"
    rm -rf "$TEMP_DIR"
    exit 0
fi

TODAY=$(get_today_date)
LOG_FILE="/var/log/exim_mainlog"
HOSTNAME=$(hostname 2>/dev/null || echo "Unknown")
CURRENT_TIME=$($DATE_CMD "+%Y-%m-%d %H:%M:%S")

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "$($DATE_CMD): Error - Log file $LOG_FILE not found" >> "$ERROR_LOG"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 2. Get today's email statistics
echo "$($DATE_CMD): Gathering today's email statistics..." >> "$ERROR_LOG"

# Overall traffic with error handling
RECEIVED=$($GREP_CMD "$TODAY" $LOG_FILE 2>/dev/null | $GREP_CMD "<=" | $GREP_CMD -v "<= <>" | $GREP_CMD -v "U=mailnull" | $WC_CMD -l)
SENT=$($GREP_CMD "$TODAY" $LOG_FILE 2>/dev/null | $GREP_CMD "=>" | $WC_CMD -l)
FAILED=$($GREP_CMD "$TODAY" $LOG_FILE 2>/dev/null | $GREP_CMD "\*\*" | $WC_CMD -l)
BOUNCES=$($GREP_CMD "$TODAY" $LOG_FILE 2>/dev/null | $GREP_CMD "<= <>" | $WC_CMD -l)

# Ensure variables are numbers
RECEIVED=${RECEIVED:-0}
SENT=${SENT:-0}
FAILED=${FAILED:-0}
BOUNCES=${BOUNCES:-0}

# 3. Analyze queue status
FROZEN_COUNT=$($EXIM_CMD -bp 2>/dev/null | $GREP_CMD -c "frozen" || echo "0")
ACTIVE_COUNT=$((QUEUE_COUNT - FROZEN_COUNT))

# 4. Extract sender information from current queue
QUEUE_DETAIL_DATA=$($EXIM_CMD -bp 2>/dev/null)
echo "$QUEUE_DETAIL_DATA" > "$QUEUE_DETAIL"

# Extract sender email addresses
$GREP_CMD -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$QUEUE_DETAIL" 2>/dev/null | \
    $SORT_CMD | $UNIQ_CMD -c | $SORT_CMD -rn | $HEAD_CMD -15 > "$SENDER_LIST"

# Extract domains
$GREP_CMD -oE '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$QUEUE_DETAIL" 2>/dev/null | \
    $SED_CMD 's/@//' | $SORT_CMD | $UNIQ_CMD -c | $SORT_CMD -rn | $HEAD_CMD -10 > "$DOMAIN_LIST"

# Extract cPanel users
$GREP_CMD -oE '/home/[^/]+/' "$QUEUE_DETAIL" 2>/dev/null | \
    $CUT_CMD -d'/' -f3 | $SORT_CMD | $UNIQ_CMD -c | $SORT_CMD -rn | $HEAD_CMD -10 > "$CPANEL_LIST"

# Extract CWD paths from today's logs
$GREP_CMD "$TODAY" $LOG_FILE 2>/dev/null | $GREP_CMD "cwd=" | \
    $GREP_CMD -oP 'cwd=\K[^ ]+' 2>/dev/null | $SORT_CMD | $UNIQ_CMD -c | $SORT_CMD -rn | $HEAD_CMD -10 > "$CWD_LIST"

# 5. Get hourly statistics
echo "$($DATE_CMD): Analyzing hourly patterns..." >> "$ERROR_LOG"
for hour in {0..23}; do
    hour_padded=$(printf "%02d" $hour)
    hour_total=$($GREP_CMD "$TODAY $hour_padded:" $LOG_FILE 2>/dev/null | $WC_CMD -l)
    echo "$hour_padded:$hour_total" >> "$HOURLY_STATS"
done

# 6. Find cron email users
echo "$($DATE_CMD): Checking cron email senders..." >> "$ERROR_LOG"
$GREP_CMD "$TODAY" $LOG_FILE 2>/dev/null | $GREP_CMD "cwd=" | \
    $GREP_CMD -E "/home/" | $GREP_CMD -oP 'cwd=/home/\K[^/]+' 2>/dev/null | \
    $SORT_CMD | $UNIQ_CMD -c | $SORT_CMD -rn | $HEAD_CMD -10 > "$CRON_USERS"

# 7. Analyze high-risk messages from queue
echo "$($DATE_CMD): Identifying high-risk messages..." >> "$ERROR_LOG"
$EXIM_CMD -bp 2>/dev/null | $GREP_CMD -E '^[0-9]+[a-zA-Z]' | $HEAD_CMD -20 | while read line; do
    msg_id=$(echo "$line" | $AWK_CMD '{print $3}')
    frozen=$(echo "$line" | $GREP_CMD -c "frozen")
    size=$(echo "$line" | $AWK_CMD '{print $2}')
    
    # Check if it's a bounce message
    if $EXIM_CMD -Mvh "$msg_id" 2>/dev/null | $GREP_CMD -q "Auto-Submitted: auto-replied\|Precedence: bulk\|X-Mailer: PHP"; then
        echo "$msg_id|$size|$frozen|SPAM_SIGNATURE" >> "$HIGH_RISK"
    elif [ "$frozen" -eq 1 ]; then
        echo "$msg_id|$size|$frozen|FROZEN" >> "$HIGH_RISK"
    fi
done

# 8. Get most active sender
MOST_ACTIVE=$($HEAD_CMD -1 "$SENDER_LIST" 2>/dev/null | $AWK_CMD '{$1=""; print $0}' | $SED_CMD 's/^[ \t]*//')
MOST_ACTIVE_COUNT=$($HEAD_CMD -1 "$SENDER_LIST" 2>/dev/null | $AWK_CMD '{print $1}')

# Set defaults if empty
MOST_ACTIVE=${MOST_ACTIVE:-"None"}
MOST_ACTIVE_COUNT=${MOST_ACTIVE_COUNT:-0}

# 9. Get top cPanel user
TOP_CPANEL=$($HEAD_CMD -1 "$CPANEL_LIST" 2>/dev/null | $AWK_CMD '{print $2}')
TOP_CPANEL_COUNT=$($HEAD_CMD -1 "$CPANEL_LIST" 2>/dev/null | $AWK_CMD '{print $1}')

# 10. Check for suspicious TLDs
SUSPICIOUS_DOMAINS=$($GREP_CMD -E '\.(xyz|top|work|date|stream|bid|trade|webcam|science|party|review|loan|win|men|download|racing|accountant|faith|bar|rest|click|link|help|gdn|ooo|cfd|sbs|icu|cyou|bond|monster)$' "$DOMAIN_LIST" 2>/dev/null | $HEAD_CMD -5)

# 11. Find peak hour
PEAK_HOUR=$($SORT_CMD -t: -k2 -rn "$HOURLY_STATS" 2>/dev/null | $HEAD_CMD -1 | $CUT_CMD -d: -f1)
PEAK_TOTAL=$($SORT_CMD -t: -k2 -rn "$HOURLY_STATS" 2>/dev/null | $HEAD_CMD -1 | $CUT_CMD -d: -f2)

# Set defaults
PEAK_HOUR=${PEAK_HOUR:-"N/A"}
PEAK_TOTAL=${PEAK_TOTAL:-0}

# 12. Build comprehensive report
{
    echo "🚨 <b>CRITICAL ALERT: Mail Queue Overflow</b> 🚨"
    echo ""
    echo "🖥 <b>Server:</b> ${HOSTNAME}"
    echo "⏰ <b>Time:</b> ${CURRENT_TIME}"
    echo ""
    echo "═══════════════════════════════════════════"
    echo "📦 <b>EXIM QUEUE STATUS</b>"
    echo "═══════════════════════════════════════════"
    echo "➖ Total Messages: <b>${QUEUE_COUNT}</b>"
    echo "❄️ Frozen: <b>${FROZEN_COUNT}</b>"
    echo "✅ Active: <b>${ACTIVE_COUNT}</b>"
    echo ""
    echo "═══════════════════════════════════════════"
    echo "📊 <b>TODAY'S TRAFFIC OVERVIEW</b>"
    echo "═══════════════════════════════════════════"
    echo "📥 Received: <b>${RECEIVED}</b>"
    echo "📤 Sent: <b>${SENT}</b>"
    echo "❌ Failed: <b>${FAILED}</b>"
    echo "🔄 Bounces: <b>${BOUNCES}</b>"
    echo "📈 Total: <b>$((RECEIVED + SENT))</b>"
    echo ""
    echo "═══════════════════════════════════════════"
    echo "🔥 <b>MOST ACTIVE SENDER (QUEUE)</b>"
    echo "═══════════════════════════════════════════"
    echo "<code>${MOST_ACTIVE}</code>"
    echo "📧 Emails in queue: <b>${MOST_ACTIVE_COUNT}</b>"
    echo ""
    
    if [ -n "$TOP_CPANEL" ]; then
        echo "═══════════════════════════════════════════"
        echo "👤 <b>TOP CPANEL ACCOUNT</b>"
        echo "═══════════════════════════════════════════"
        echo "User: <b>${TOP_CPANEL}</b>"
        echo "Emails: <b>${TOP_CPANEL_COUNT}</b>"
        echo ""
    fi
    
    echo "═══════════════════════════════════════════"
    echo "📧 <b>TOP SENDERS IN QUEUE</b>"
    echo "═══════════════════════════════════════════"
    echo "<pre>"
    $HEAD_CMD -10 "$SENDER_LIST" 2>/dev/null
    echo "</pre>"
    echo ""
    
    if [ -s "$CRON_USERS" ]; then
        echo "═══════════════════════════════════════════"
        echo "⏰ <b>CRON EMAIL SENDERS (TODAY)</b>"
        echo "═══════════════════════════════════════════"
        echo "<pre>"
        cat "$CRON_USERS"
        echo "</pre>"
        echo ""
    fi
    
    if [ -s "$CWD_LIST" ]; then
        echo "═══════════════════════════════════════════"
        echo "📂 <b>TOP SCRIPT PATHS (CWD)</b>"
        echo "═══════════════════════════════════════════"
        echo "<pre>"
        cat "$CWD_LIST"
        echo "</pre>"
        echo ""
    fi
    
    echo "═══════════════════════════════════════════"
    echo "🌐 <b>TOP SENDING DOMAINS</b>"
    echo "═══════════════════════════════════════════"
    echo "<pre>"
    cat "$DOMAIN_LIST" 2>/dev/null
    echo "</pre>"
    echo ""
    
    if [ -n "$SUSPICIOUS_DOMAINS" ]; then
        echo "═══════════════════════════════════════════"
        echo "⚠️ <b>SUSPICIOUS DOMAINS DETECTED</b>"
        echo "═══════════════════════════════════════════"
        echo "<pre>"
        echo "$SUSPICIOUS_DOMAINS"
        echo "</pre>"
        echo ""
    fi
    
    echo "═══════════════════════════════════════════"
    echo "⏰ <b>HOURLY TRAFFIC PEAK</b>"
    echo "═══════════════════════════════════════════"
    echo "Peak Hour: <b>${PEAK_HOUR}:00</b>"
    echo "Messages: <b>${PEAK_TOTAL}</b>"
    echo ""
    
    if [ -s "$HIGH_RISK" ]; then
        echo "═══════════════════════════════════════════"
        echo "🚨 <b>HIGH-RISK MESSAGES DETECTED</b>"
        echo "═══════════════════════════════════════════"
        echo "<pre>"
        $HEAD_CMD -5 "$HIGH_RISK" | while IFS='|' read id size frozen reason; do
            printf "%-12s %8s %s\n" "$id" "$size" "$reason"
        done
        echo "</pre>"
        echo ""
    fi
    
    echo "═══════════════════════════════════════════"
    echo "⚡ <b>IMMEDIATE ACTIONS</b>"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "1️⃣ <b>Remove emails from top sender:</b>"
    echo "<code>exiqgrep -i -f ${MOST_ACTIVE} | xargs exim -Mrm</code>"
    echo ""
    echo "2️⃣ <b>Remove all frozen messages:</b>"
    echo "<code>exim -bp | exiqgrep -z -i | xargs exim -Mrm</code>"
    echo ""
    
    if [ -n "$TOP_CPANEL" ]; then
        echo "3️⃣ <b>Check cPanel account activity:</b>"
        echo "<code>grep cwd.*${TOP_CPANEL} /var/log/exim_mainlog | tail -20</code>"
        echo ""
        echo "4️⃣ <b>View user's cron jobs:</b>"
        echo "<code>crontab -l -u ${TOP_CPANEL}</code>"
        echo ""
    fi
    
    echo "🛡 <b>PREVENTION TIPS:</b>"
    echo "• Check for compromised email passwords"
    echo "• Scan for vulnerable contact forms/scripts"
    echo "• Review cron jobs for suspicious entries"
    echo "• Enable SMTP restrictions in WHM"
    
} > "$REPORT_FILE"

# 13. Send report to Telegram
echo "$($DATE_CMD): Sending comprehensive report to Telegram..." >> "$ERROR_LOG"
send_telegram "$(cat $REPORT_FILE)"

# 14. Cleanup (keep error log for debugging, remove after 7 days)
find /tmp -name "exim_telegram_*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null

# Clean current temp dir but keep error log for debugging
# rm -rf "$TEMP_DIR"

exit 0
