#!/bin/bash

# ======================================================================
# ╔══════════════════════════════════════════════════════════════════╗
# ║     EXIM QUEUE SPAM ANALYZER - TELEGRAM ALERT SYSTEM            ║
# ╚══════════════════════════════════════════════════════════════════╝
# ======================================================================

# Telegram Configuration
CHAT_ID="992809735"
BOT_TOKEN="8770766348:AAEcXgiu12B6KSnRzgbwiRe2Ty3sRG8eExk"

# Temporary files
TEMP_DIR="/tmp/exim_telegram_$$"
mkdir -p "$TEMP_DIR"
QUEUE_DETAIL="$TEMP_DIR/queue_detail.txt"
SENDER_LIST="$TEMP_DIR/senders.txt"
DOMAIN_LIST="$TEMP_DIR/domains.txt"
CPANEL_LIST="$TEMP_DIR/cpanel.txt"
CWD_LIST="$TEMP_DIR/cwd.txt"
HOURLY_STATS="$TEMP_DIR/hourly.txt"
CRON_USERS="$TEMP_DIR/cron_users.txt"
HIGH_RISK="$TEMP_DIR/high_risk.txt"
REPORT_FILE="$TEMP_DIR/report.txt"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run this script as root."
    exit 1
fi

# Function to send message to Telegram
send_telegram() {
    local message="$1"
    echo "$message" > "$TEMP_DIR/telegram_msg.txt"
    
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text@$TEMP_DIR/telegram_msg.txt" \
        -d "parse_mode=HTML")
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo "✅ Message sent to Telegram successfully"
        return 0
    else
        echo "❌ Failed to send message"
        return 1
    fi
}

# Function to get today's date in log format
get_today_date() {
    date +"%Y-%m-%d"
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
QUEUE_COUNT=$(exim -bpc 2>/dev/null)
if [ -z "$QUEUE_COUNT" ]; then
    echo "Error executing exim -bpc command"
    exit 1
fi

echo "📊 Total emails in queue: $QUEUE_COUNT"

# Stop if queue count is below threshold
if [ "$QUEUE_COUNT" -le 100 ]; then
    echo "✅ Queue count is below 100. No alert needed."
    rm -rf "$TEMP_DIR"
    exit 0
fi

TODAY=$(get_today_date)
LOG_FILE="/var/log/exim_mainlog"
HOSTNAME=$(hostname)
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# 2. Get today's email statistics
echo "📈 Gathering today's email statistics..."

# Overall traffic
RECEIVED=$(grep "$TODAY" $LOG_FILE 2>/dev/null | grep "<=" | grep -v "<= <>" | grep -v "U=mailnull" | wc -l)
SENT=$(grep "$TODAY" $LOG_FILE 2>/dev/null | grep "=>" | wc -l)
FAILED=$(grep "$TODAY" $LOG_FILE 2>/dev/null | grep "\*\*" | wc -l)
BOUNCES=$(grep "$TODAY" $LOG_FILE 2>/dev/null | grep "<= <>" | wc -l)

# 3. Analyze queue status
FROZEN_COUNT=$(exim -bp 2>/dev/null | grep -c "frozen")
ACTIVE_COUNT=$((QUEUE_COUNT - FROZEN_COUNT))

# 4. Extract sender information from current queue
QUEUE_DETAIL_DATA=$(exim -bp 2>/dev/null)
echo "$QUEUE_DETAIL_DATA" > "$QUEUE_DETAIL"

# Extract sender email addresses
grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$QUEUE_DETAIL" | sort | uniq -c | sort -rn | head -15 > "$SENDER_LIST"

# Extract domains
grep -oE '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$QUEUE_DETAIL" | sed 's/@//' | sort | uniq -c | sort -rn | head -10 > "$DOMAIN_LIST"

# Extract cPanel users
grep -oE '/home/[^/]+/' "$QUEUE_DETAIL" | cut -d'/' -f3 | sort | uniq -c | sort -rn | head -10 > "$CPANEL_LIST"

# Extract CWD paths from today's logs
grep "$TODAY" $LOG_FILE 2>/dev/null | grep "cwd=" | grep -oP 'cwd=\K[^ ]+' | sort | uniq -c | sort -rn | head -10 > "$CWD_LIST"

# 5. Get hourly statistics
echo "⏰ Analyzing hourly patterns..."
for hour in {0..23}; do
    hour_padded=$(printf "%02d" $hour)
    hour_total=$(grep "$TODAY $hour_padded:" $LOG_FILE 2>/dev/null | wc -l)
    echo "$hour_padded:$hour_total" >> "$HOURLY_STATS"
done

# 6. Find cron email users
echo "🔍 Checking cron email senders..."
grep "$TODAY" $LOG_FILE 2>/dev/null | grep "cwd=" | grep -E "/home/" | grep -oP 'cwd=/home/\K[^/]+' | sort | uniq -c | sort -rn | head -10 > "$CRON_USERS"

# 7. Analyze high-risk messages from queue
echo "🚨 Identifying high-risk messages..."
exim -bp 2>/dev/null | grep -E '^[0-9]+[a-zA-Z]' | head -20 | while read line; do
    msg_id=$(echo "$line" | awk '{print $3}')
    frozen=$(echo "$line" | grep -c "frozen")
    size=$(echo "$line" | awk '{print $2}')
    
    # Check if it's a bounce message
    if exim -Mvh "$msg_id" 2>/dev/null | grep -q "Auto-Submitted: auto-replied\|Precedence: bulk\|X-Mailer: PHP"; then
        echo "$msg_id|$size|$frozen|SPAM_SIGNATURE" >> "$HIGH_RISK"
    elif [ "$frozen" -eq 1 ]; then
        echo "$msg_id|$size|$frozen|FROZEN" >> "$HIGH_RISK"
    fi
done

# 8. Get most active sender
MOST_ACTIVE=$(head -1 "$SENDER_LIST" 2>/dev/null | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
MOST_ACTIVE_COUNT=$(head -1 "$SENDER_LIST" 2>/dev/null | awk '{print $1}')

# 9. Get top cPanel user
TOP_CPANEL=$(head -1 "$CPANEL_LIST" 2>/dev/null | awk '{print $2}')
TOP_CPANEL_COUNT=$(head -1 "$CPANEL_LIST" 2>/dev/null | awk '{print $1}')

# 10. Check for suspicious TLDs
SUSPICIOUS_DOMAINS=$(grep -E '\.(xyz|top|work|date|stream|bid|trade|webcam|science|party|review|loan|win|men|download|racing|accountant|faith|bar|rest|click|link|help|gdn|ooo|cfd|sbs|icu|cyou|bond|monster)$' "$DOMAIN_LIST" | head -5)

# 11. Find peak hour
PEAK_HOUR=$(sort -t: -k2 -rn "$HOURLY_STATS" | head -1 | cut -d: -f1)
PEAK_TOTAL=$(sort -t: -k2 -rn "$HOURLY_STATS" | head -1 | cut -d: -f2)

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
    cat "$SENDER_LIST" 2>/dev/null | head -10
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
        head -5 "$HIGH_RISK" | while IFS='|' read id size frozen reason; do
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
echo ""
echo "📤 Sending comprehensive report to Telegram..."
send_telegram "$(cat $REPORT_FILE)"

# 14. Display summary on console
echo ""
echo "========================================="
echo "📊 QUEUE ANALYSIS SUMMARY"
echo "========================================="
echo "Server:        $HOSTNAME"
echo "Time:          $CURRENT_TIME"
echo "Queue Total:   $QUEUE_COUNT"
echo "Queue Frozen:  $FROZEN_COUNT"
echo "Today Traffic: $((RECEIVED + SENT)) emails"
echo ""
echo "🔥 MOST ACTIVE: $MOST_ACTIVE ($MOST_ACTIVE_COUNT emails)"
echo ""

if [ -n "$TOP_CPANEL" ]; then
    echo "👤 TOP CPANEL: $TOP_CPANEL ($TOP_CPANEL_COUNT emails)"
    echo ""
fi

echo "📧 Top 5 Senders:"
head -5 "$SENDER_LIST" 2>/dev/null
echo ""

echo "🌐 Top 5 Domains:"
head -5 "$DOMAIN_LIST" 2>/dev/null
echo ""

if [ -s "$CRON_USERS" ]; then
    echo "⏰ Top Cron Senders:"
    head -3 "$CRON_USERS"
    echo ""
fi

echo "========================================="
echo "✅ Report sent to Telegram successfully!"

# 15. Cleanup
rm -rf "$TEMP_DIR"
