#!/bin/bash

#===================================================
# MailChannels & SMTP Debug Script v1.2 - Final Fix
# For cPanel servers with Imunify360
# Date: 2026-05-08
#===================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Default timeout
TIMEOUT=5
MAILCHANNELS_HOST="smtp.mailchannels.net"
MAILCHANNELS_PORT=25
LOG_FILE="/tmp/mail_debug_$(date +%Y%m%d_%H%M%S).log"

#===================================================
# Helper Functions
#===================================================

print_header() {
    echo -e "\n${BOLD}${CYAN}========================================="
    echo -e "  $1"
    echo -e "=========================================${NC}\n"
}

print_ok() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_fail() {
    echo -e "${RED}✗ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_test() {
    echo -e "${MAGENTA}● $1${NC}"
}

print_cmd() {
    echo -e "   ${CYAN}$1${NC}"
}

# Test port with nc
test_port_nc() {
    local host=$1
    local port=$2
    local timeout=${3:-$TIMEOUT}

    result=$(nc -zv -w $timeout $host $port 2>&1)
    if echo "$result" | grep -q "Connected\|succeeded\|open"; then
        return 0
    else
        return 1
    fi
}

# Test port with bash built-in
test_port_bash() {
    local host=$1
    local port=$2
    local timeout=${3:-$TIMEOUT}

    timeout $timeout bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null && return 0 || return 1
}

#===================================================
# Section 1: System Information
#===================================================

print_header "Section 1: System Information"

print_test "Hostname: $(hostname)"
print_test "Kernel: $(uname -r)"
print_test "OS: $(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
print_test "Date: $(date '+%Y-%m-%d %H:%M:%S')"

if [ -f "/usr/local/cpanel/cpanel" ]; then
    print_ok "cPanel installed: version $(cat /usr/local/cpanel/version 2>/dev/null || echo 'Unknown')"
else
    print_warn "cPanel not installed"
fi

if [ -f "/usr/bin/imunify360-agent" ]; then
    print_ok "Imunify360 installed: version $(imunify360-agent version 2>/dev/null || echo 'Unknown')"
else
    print_warn "Imunify360 not installed"
fi

if [ -f "/usr/sbin/exim" ]; then
    exim_version=$(/usr/sbin/exim -bV 2>/dev/null | head -1)
    print_ok "Exim: $exim_version"
else
    print_warn "Exim not found"
fi

#===================================================
# Section 2: Firewall Status
#===================================================

print_header "Section 2: Firewall Status"

if [ -f "/etc/csf/csf.conf" ]; then
    print_ok "CSF installed"
    smtp_block=$(grep -i '^SMTP_BLOCK' /etc/csf/csf.conf | grep -o '[0-9]')
    if [ "$smtp_block" == "1" ]; then
        print_fail "SMTP_BLOCK in CSF is ENABLED (=1)"
        print_info "Fix: Set SMTP_BLOCK = \"0\" in /etc/csf/csf.conf and run csf -r"
    else
        print_ok "SMTP_BLOCK in CSF is disabled"
    fi
else
    print_info "CSF not installed"
fi

if [ -f "/etc/sysconfig/imunify360/imunify360-merged.config" ]; then
    print_test "Imunify360 SMTP_BLOCKING settings:"

    smtp_blocking_enabled=$(awk '/^SMTP_BLOCKING:/{found=1} found && /^  enable:/{print $2; exit}' /etc/sysconfig/imunify360/imunify360-merged.config)

    if [ "$smtp_blocking_enabled" == "true" ]; then
        print_fail "SMTP_BLOCKING is ENABLED (enable: true)"
        print_info "Fix: imunify360-agent smtp-block disable"
    else
        print_ok "SMTP_BLOCKING is disabled (enable: false)"
        print_info "Blocked ports in config (inactive):"
        awk '/^SMTP_BLOCKING:/{found=1} found && /^  ports:/{found_ports=1; next} found_ports && /^  -/{print "    Port:", $2} found_ports && /^  [a-z]/{exit}' /etc/sysconfig/imunify360/imunify360-merged.config
    fi
fi

if systemctl is-active firewalld &>/dev/null; then
    print_warn "firewalld is ACTIVE"
else
    print_info "firewalld is not active"
fi

#===================================================
# Section 3: iptables Inspection
#===================================================

print_header "Section 3: iptables Inspection"

print_test "Checking OUTPUT rules for port 25..."

if iptables-save 2>/dev/null | grep -E 'dport 25|--dport 25' | grep -E 'DROP|REJECT' > /tmp/mail_debug_iptables.txt; then
    print_fail "DROP/REJECT rule found for port 25:"
    cat /tmp/mail_debug_iptables.txt | sed 's/^/    /'
else
    print_ok "No DROP/REJECT rules for port 25 in iptables"
fi

print_test "Checking Imunify360 OUTPUT chains..."

if iptables -L OUTPUT -n 2>/dev/null | grep -q 'OUTPUT_imunify360'; then
    print_info "OUTPUT_imunify360 chain exists"

    if iptables -L OUTPUT_imunify360_bp -n 2>/dev/null | grep -q 'REJECT'; then
        reject_line=$(iptables -L OUTPUT_imunify360_bp -n --line-numbers 2>/dev/null | grep 'REJECT')
        print_warn "Catch-all REJECT rule found:"
        echo "    $reject_line"
    fi

    if ipset list i360.ipv4.output-ports-tcp 2>/dev/null | grep -q '25'; then
        print_ok "Port 25 exists in allowed ipset (i360.ipv4.output-ports-tcp)"
    else
        print_fail "Port 25 NOT in allowed ipset!"
        print_info "Fix: ipset add i360.ipv4.output-ports-tcp 25"
    fi
fi

print_test "OUTPUT chain summary:"
iptables -L OUTPUT -n -v --line-numbers 2>/dev/null | head -5 | sed 's/^/    /'

#===================================================
# Section 4: SMTP Connectivity Tests
#===================================================

print_header "Section 4: SMTP Connectivity Tests"

declare -A SMTP_TARGETS=(
    ["MailChannels:25"]="$MAILCHANNELS_HOST:25"
    ["MailChannels:587"]="$MAILCHANNELS_HOST:587"
    ["MailChannels:465"]="$MAILCHANNELS_HOST:465"
    ["MailChannels:2525"]="$MAILCHANNELS_HOST:2525"
    ["Gmail:25"]="smtp.gmail.com:25"
    ["Gmail:587"]="smtp.gmail.com:587"
    ["Gmail:465"]="smtp.gmail.com:465"
    ["Outlook:25"]="smtp-mail.outlook.com:25"
    ["Yahoo:25"]="smtp.mail.yahoo.com:25"
)

for target in "MailChannels:25" "MailChannels:587" "MailChannels:465" "MailChannels:2525" "Gmail:25" "Gmail:587" "Gmail:465" "Outlook:25" "Yahoo:25"; do
    host=$(echo ${SMTP_TARGETS[$target]} | cut -d: -f1)
    port=$(echo ${SMTP_TARGETS[$target]} | cut -d: -f2)

    print_test "Testing $target ($host:$port)..."

    if test_port_nc "$host" "$port"; then
        print_ok "$target - OPEN"
    elif test_port_bash "$host" "$port"; then
        print_ok "$target - OPEN (via bash)"
    else
        print_fail "$target - CLOSED or TIMEOUT"
    fi
done

#===================================================
# Section 5: MailChannels Configuration
#===================================================

print_header "Section 5: MailChannels Configuration"

if [ -f "/etc/exim.conf" ]; then
    print_test "Searching for MailChannels settings in Exim..."

    if grep -qi 'mailchannels' /etc/exim.conf; then
        print_ok "MailChannels settings found in /etc/exim.conf"

        route=$(grep -i 'route_list.*mailchannels' /etc/exim.conf 2>/dev/null | head -1)
        if [ -n "$route" ]; then
            echo -e "    ${CYAN}Route:${NC} $route"
        fi

        transport=$(grep -i 'transport.*mailchannels' /etc/exim.conf 2>/dev/null | head -1)
        if [ -n "$transport" ]; then
            echo -e "    ${CYAN}Transport:${NC} $transport"
        fi

        router=$(grep -B5 'mailchannels_smtp' /etc/exim.conf 2>/dev/null | grep '^\w' | head -1)
        if [ -n "$router" ]; then
            echo -e "    ${CYAN}Router:${NC} $router"
        fi
    else
        print_fail "MailChannels settings NOT found in /etc/exim.conf!"
    fi
fi

print_test "Checking MailChannels credentials..."
if [ -f "/etc/mailchannels/exim/smtpusername" ]; then
    username=$(cat /etc/mailchannels/exim/smtpusername 2>/dev/null | tr -d '\n')
    print_ok "Username file found: ${username:0:15}..."
else
    print_fail "Username file NOT found: /etc/mailchannels/exim/smtpusername"
fi

if [ -f "/etc/mailchannels/exim/smtppassword" ]; then
    pass_length=$(cat /etc/mailchannels/exim/smtppassword 2>/dev/null | wc -c)
    print_ok "Password file found (length: $pass_length chars)"
else
    print_fail "Password file NOT found: /etc/mailchannels/exim/smtppassword"
fi

#===================================================
# Section 6: Recent Exim Errors
#===================================================

print_header "Section 6: Recent Exim Errors"

if [ -f "/var/log/exim_mainlog" ]; then
    print_test "MailChannels related errors in last 24 hours:"

    errors=$(grep -i 'mailchannels\|all hosts.*failing\|retry time not reached' /var/log/exim_mainlog 2>/dev/null | tail -20)

    if [ -n "$errors" ]; then
        print_warn "Related errors found:"
        echo "$errors" | while read line; do
            echo -e "    ${YELLOW}$line${NC}"
        done

        all_hosts_count=$(echo "$errors" | grep -c 'all hosts.*failing')
        retry_count=$(echo "$errors" | grep -c 'retry time not reached')

        if [ "$all_hosts_count" -gt 0 ]; then
            print_fail "Count of 'all hosts failing' errors: $all_hosts_count"
        fi
        if [ "$retry_count" -gt 0 ]; then
            print_fail "Count of 'retry time not reached' errors: $retry_count"
        fi
    else
        print_ok "No MailChannels related errors in last 24 hours"
    fi

    frozen=$(exim -bp 2>/dev/null | grep -c 'frozen' || echo "0")
    if [ "$frozen" -gt 0 ]; then
        print_warn "$frozen frozen messages in queue"
        print_info "View with: exim -bp | grep frozen"
    else
        print_ok "No frozen messages in queue"
    fi

    queue_size=$(exim -bpc 2>/dev/null || echo "0")
    print_info "Total messages in queue: $queue_size"
else
    print_warn "/var/log/exim_mainlog not found"
fi

#===================================================
# Section 7: Direct SMTP Test (MailChannels)
#===================================================

print_header "Section 7: Direct SMTP Test (MailChannels)"

print_test "Attempting direct SMTP connection to MailChannels..."

smtp_response=$(
    (
        echo "EHLO $(hostname)"
        sleep 1
        echo "QUIT"
    ) | timeout 10 nc $MAILCHANNELS_HOST 25 2>/dev/null
)

if [ -n "$smtp_response" ]; then
    print_ok "SMTP connection established, response received:"
    echo "$smtp_response" | head -3 | sed 's/^/    /'
else
    print_fail "SMTP connection FAILED - no response from $MAILCHANNELS_HOST:25"
fi

if command -v telnet &>/dev/null; then
    print_test "Testing with telnet..."
    timeout 5 telnet $MAILCHANNELS_HOST 25 2>&1 | head -3 | sed 's/^/    /'
fi

#===================================================
# Section 8: DNS and Resolution Checks
#===================================================

print_header "Section 8: DNS and Resolution Checks"

print_test "Resolving $MAILCHANNELS_HOST..."
if host $MAILCHANNELS_HOST &>/dev/null || nslookup $MAILCHANNELS_HOST &>/dev/null; then
    ip=$(host $MAILCHANNELS_HOST 2>/dev/null | grep 'has address' | head -1 | awk '{print $NF}')
    print_ok "$MAILCHANNELS_HOST resolves to: $ip"
else
    print_fail "Cannot resolve $MAILCHANNELS_HOST"
fi

server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
if [ -n "$server_ip" ]; then
    print_test "Server public IP: $server_ip"
    ptr=$(host $server_ip 2>/dev/null | grep 'pointer' | awk '{print $NF}')
    if [ -n "$ptr" ]; then
        print_ok "Reverse DNS (PTR): $ptr"
    else
        print_warn "No reverse DNS (PTR) record found"
    fi
fi

#===================================================
# Section 9: Test Email Suggestion
#===================================================

print_header "Section 9: Test Email Suggestion"

print_info "To send a test email, run:"
print_cmd "echo \"Test from \$(hostname) at \$(date)\" | mail -s \"Test Email \$(date +%s)\" -v your@email.com"
echo ""
print_info "Then check logs immediately:"
print_cmd "tail -50 /var/log/exim_mainlog"
print_cmd "exim -bp"

#===================================================
# Section 10: Summary and Diagnostics (FULLY FIXED)
#===================================================

print_header "Section 10: Summary and Diagnostics"

echo ""
echo -e "${BOLD}Status Summary:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

issues=0
suggestions=()

# Check port 25 access
if ! test_port_nc "$MAILCHANNELS_HOST" "$MAILCHANNELS_PORT" && ! test_port_bash "$MAILCHANNELS_HOST" "$MAILCHANNELS_PORT"; then
    ((issues++))
    echo -e "${RED}[Issue $issues] Port 25 to MailChannels is NOT accessible${NC}"

    if test_port_nc "smtp.gmail.com" 587; then
        echo "   → Port 587 is OPEN but port 25 is BLOCKED"
        echo "   → Likely blocked by datacenter or ISP"
    fi

    if test_port_nc "$MAILCHANNELS_HOST" 587; then
        echo "   → MailChannels port 587 is OPEN - consider switching to port 587"
        suggestions+=("Change MailChannels port from 25 to 587 in /etc/exim.conf route_list")
    fi

    suggestions+=("Contact hosting provider/datacenter to unblock outgoing port 25")
fi

# Check iptables
if iptables-save 2>/dev/null | grep -E 'dport 25|--dport 25' | grep -qE 'DROP|REJECT'; then
    ((issues++))
    echo -e "${RED}[Issue $issues] Firewall is blocking port 25${NC}"
    suggestions+=("Remove DROP rule for port 25 from iptables")
fi

# Check frozen messages
if [ -f "/var/log/exim_mainlog" ]; then
    frozen=$(exim -bp 2>/dev/null | grep -c 'frozen' || echo "0")
    if [ "$frozen" -gt 10 ]; then
        ((issues++))
        echo -e "${RED}[Issue $issues] High number of frozen messages ($frozen)${NC}"
        suggestions+=("Clear frozen messages: exim -bpr | grep frozen | awk '{print \$3}' | xargs exim -Mrm")
    fi

    unique_domains=$(grep 'all hosts for.*have been failing' /var/log/exim_mainlog 2>/dev/null | grep -oP "for '\K[^']+" | sort -u | wc -l)
    if [ "$unique_domains" -gt 5 ]; then
        echo -e "${YELLOW}   → $unique_domains unique domains failing - indicates systemic port 25 issue${NC}"
    fi
fi

if [ $issues -eq 0 ]; then
    echo -e "${GREEN}✓ No obvious issues found${NC}"
    echo ""
    print_info "Send a test email and monitor logs to verify"
else
    echo ""
    echo -e "${RED}Total issues found: $issues${NC}"
    echo ""
    echo -e "${BOLD}Recommended Solutions (in order of priority):${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    num=1
    for suggestion in "${suggestions[@]}"; do
        echo -e "${CYAN}$num.${NC} $suggestion"
        ((num++))
    done

    echo ""
    echo -e "${BOLD}Quick Fix Commands:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Switch MailChannels to port 587 (if supported):"
    print_cmd "sed -i 's|smtp.mailchannels.net::25|smtp.mailchannels.net::587|g' /etc/exim.conf"
    print_cmd "systemctl restart exim"
    echo ""
    echo "2. Clear frozen queue (after fixing port issue):"
    print_cmd "exim -bpr | grep frozen | awk '{print \$3}' | xargs exim -Mrm"
    echo ""
    echo "3. Force retry all queued messages (after fixing port issue):"
    print_cmd "exim -qff"
    echo ""
    echo "4. Disable Imunify360 SMTP block (if enabled):"
    print_cmd "imunify360-agent smtp-block disable"
    echo ""
    echo "5. Test specific destination domain:"
    print_cmd "dig MX gmail.com +short"
    echo ""
    echo "6. Monitor Exim log in real-time:"
    print_cmd "tail -f /var/log/exim_mainlog | grep -i 'mailchannels\|failing\|frozen'"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Report Complete - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Save summary to log file
{
    echo "Mail Debug Report - $(date)"
    echo "Server: $(hostname)"
    echo "Issues Found: $issues"
    echo "Port 25 Status: $(test_port_nc $MAILCHANNELS_HOST 25 && echo OPEN || echo CLOSED)"
    echo "Port 587 Status: $(test_port_nc $MAILCHANNELS_HOST 587 && echo OPEN || echo CLOSED)"
    echo "Frozen Messages: $(exim -bp 2>/dev/null | grep -c frozen || echo 0)"
} >> "$LOG_FILE" 2>/dev/null

echo "Report saved to: $LOG_FILE"

# Cleanup
rm -f /tmp/mail_debug_iptables.txt
