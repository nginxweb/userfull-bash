#!/bin/bash

# Telegram Configuration
CHAT_ID="992809735"
BOT_TOKEN="8400990771:AAF1da4odhR5ScjIIA7LrYMzH1CQnZ0nuak"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run this script as root."
    exit 1
fi

# Function to send message to Telegram
send_telegram() {
    local message="$1"
    
    # Save message to temporary file
    echo "$message" > /tmp/telegram_msg.txt
    
    # Use curl with proper --data-urlencode
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text@/tmp/telegram_msg.txt" \
        -d "parse_mode=HTML")
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo "✅ Message sent to Telegram successfully"
        return 0
    else
        echo "❌ Failed to send message"
        echo "   Response: $RESPONSE"
        return 1
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
    exit 0
fi

# 2. Analyze queue status (frozen emails)
FROZEN_COUNT=$(exim -bp 2>/dev/null | grep -c "frozen")

# 3. Extract sender information DIRECTLY FROM CURRENT QUEUE
QUEUE_DETAIL=$(exim -bp 2>/dev/null)

# Extract sender email addresses from the queue
SENDER_ANALYSIS=$(echo "$QUEUE_DETAIL" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | sort | uniq -c | sort -nr | head -10)

# Extract cPanel usernames from queue messages
CPANEL_USERS=$(echo "$QUEUE_DETAIL" | grep -oE '/home/[^/]+/' | cut -d'/' -f3 | sort | uniq -c | sort -nr | head -5)

# Extract top domains sending emails from the queue
DOMAIN_ANALYSIS=$(echo "$QUEUE_DETAIL" | grep -oE '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | sed 's/@//' | sort | uniq -c | sort -nr | head -5)

# 4. Get top messages with size
TOP_MESSAGES=$(exim -bp 2>/dev/null | grep -E '^[0-9]+[a-zA-Z]' | awk '{print $3, $1}' | sort -rn | head -5 | awk '{printf "%-10s %s\n", $2, $1}')

# 5. Get the most active sender account for quick action
MOST_ACTIVE_SENDER=$(echo "$SENDER_ANALYSIS" | head -1 | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
MOST_ACTIVE_COUNT=$(echo "$SENDER_ANALYSIS" | head -1 | awk '{print $1}')

# 6. Format message with proper HTML escaping
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
HOSTNAME=$(hostname)

# Format with proper handling of empty results
[ -z "$SENDER_ANALYSIS" ] && SENDER_ANALYSIS="No email addresses found in queue"
[ -z "$CPANEL_USERS" ] && CPANEL_USERS="No cPanel users found in queue"
[ -z "$DOMAIN_ANALYSIS" ] && DOMAIN_ANALYSIS="No domains found in queue"
[ -z "$TOP_MESSAGES" ] && TOP_MESSAGES="No messages found"

# Build the message
MESSAGE="🚨 <b>CRITICAL ALERT: Mail Queue Overflow</b> 🚨

🖥 <b>Server:</b> ${HOSTNAME}
⏰ <b>Time:</b> ${CURRENT_TIME}

📦 <b>Exim Mail Queue Status:</b>
➖ Total Messages: <b>${QUEUE_COUNT}</b>
❄️ Frozen Messages: <b>${FROZEN_COUNT}</b>
📊 Active Messages: <b>$((QUEUE_COUNT - FROZEN_COUNT))</b>

🔥 <b>MOST ACTIVE SENDER:</b>
<code>${MOST_ACTIVE_SENDER}</code> (${MOST_ACTIVE_COUNT} emails)

📧 <b>Top Sender Email Addresses:</b>
<pre>${SENDER_ANALYSIS}</pre>

🌐 <b>Top Sending Domains:</b>
<pre>${DOMAIN_ANALYSIS}</pre>

👤 <b>Affected cPanel Accounts:</b>
<pre>${CPANEL_USERS}</pre>

📨 <b>Largest Messages (ID &amp; Size):</b>
<pre>${TOP_MESSAGES}</pre>

⚠️ <b>IMMEDIATE ACTIONS:</b>

1️⃣ <b>Block most active sender:</b>
<code>exiqgrep -i -f ${MOST_ACTIVE_SENDER} | xargs exim -Mrm</code>

2️⃣ <b>Remove all frozen messages:</b>
<code>exim -bp | exiqgrep -z -i | xargs exim -Mrm</code>

3️⃣ <b>Check specific cPanel account:</b>
<code>grep cwd.*username /var/log/exim_mainlog | tail -20</code>

🛡 <b>Prevention:</b>
• Change email password if account compromised
• Check for vulnerable contact forms/scripts
• Enable SMTP restrictions in WHM"

# 7. Send to Telegram
echo ""
echo "📤 Sending report to Telegram..."
send_telegram "$MESSAGE"

# 8. Display summary on console
echo ""
echo "========================================="
echo "📊 QUEUE SUMMARY REPORT"
echo "========================================="
echo "Server:        $HOSTNAME"
echo "Time:          $CURRENT_TIME"
echo "Total Queue:   $QUEUE_COUNT"
echo "Frozen:        $FROZEN_COUNT"
echo "Active:        $((QUEUE_COUNT - FROZEN_COUNT))"
echo ""
echo "🔥 MOST ACTIVE: $MOST_ACTIVE_SENDER ($MOST_ACTIVE_COUNT emails)"
echo ""
echo "👤 Top cPanel Users:"
echo "$CPANEL_USERS"
echo ""
echo "📧 Top Senders:"
echo "$SENDER_ANALYSIS"
echo ""
echo "🌐 Top Domains:"
echo "$DOMAIN_ANALYSIS"
echo ""
echo "📨 Largest Messages:"
echo "$TOP_MESSAGES"
echo "========================================="
echo "✅ Report sent to Telegram successfully!"
echo ""
echo "💡 Quick command to clear most active sender:"
echo "   exiqgrep -i -f $MOST_ACTIVE_SENDER | xargs exim -Mrm"
echo ""

# 9. Optional: Offer to clear the most active sender
read -p "❓ Do you want to remove emails from $MOST_ACTIVE_SENDER? (y/n): " CLEAR_SENDER
if [[ "$CLEAR_SENDER" =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing emails from $MOST_ACTIVE_SENDER..."
    DELETED_COUNT=$(exiqgrep -i -f "$MOST_ACTIVE_SENDER" | wc -l)
    exiqgrep -i -f "$MOST_ACTIVE_SENDER" | xargs exim -Mrm 2>/dev/null
    echo "✅ Removed $DELETED_COUNT emails"
    
    # Send confirmation to Telegram
    CONFIRM_MSG="✅ <b>Action Taken:</b> Removed ${DELETED_COUNT} emails from ${MOST_ACTIVE_SENDER}"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${CONFIRM_MSG}" \
        -d "parse_mode=HTML" > /dev/null 2>&1
fi
