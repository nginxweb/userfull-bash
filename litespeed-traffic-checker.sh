#!/usr/bin/env bash

# ================= CONFIG =================
EXPORTER_URL="http://127.0.0.1:9936/metrics"

REQ_THRESHOLD=15
CONN_THRESHOLD=70

HOSTNAME=$(hostname)
DATE=$(date "+%Y-%m-%d %H:%M:%S")

TMP_FILE=$(mktemp)
ALERT_FILE=$(mktemp)
SORTED_FILE=$(mktemp)

# ================= COLORS =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# ================= FETCH METRICS =================
clear
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}      LiteSpeed Traffic Monitor - Live Analysis${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${BLUE}▶${NC} Server: ${WHITE}$HOSTNAME${NC}"
echo -e "${BLUE}▶${NC} Time: ${WHITE}$DATE${NC}"
echo -e "${BLUE}▶${NC} Thresholds: Req/sec > ${YELLOW}$REQ_THRESHOLD${NC} OR Active Conn > ${YELLOW}$CONN_THRESHOLD${NC}"
echo ""

echo -e "${BLUE}▶${NC} Fetching metrics from exporter...${NC}"
DATA=$(curl -s --max-time 5 "$EXPORTER_URL")

if [[ -z "$DATA" ]]; then
    echo -e "${RED}✗ Error: Failed to fetch metrics${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Metrics fetched successfully${NC}"
echo ""

# ================= PARSE REQUESTS PER SECOND =================
# Extract requests per second for each vhost
echo "$DATA" | grep litespeed_requests_per_second_per_vhost | while read -r line; do
    VHOST=$(echo "$line" | sed -n 's/.*vhost="\([^"]*\)".*/\1/p')
    VALUE=$(echo "$line" | grep -oE '[0-9]+(\.[0-9]+)?$')
    [[ -z "$VHOST" || -z "$VALUE" ]] && continue
    CLEAN_VHOST=$(echo "$VHOST" | sed 's/^APVH_//')
    echo "$CLEAN_VHOST req $VALUE" >> "$TMP_FILE"
done

# ================= PARSE ACTIVE CONNECTIONS =================
# Extract current active connections for each vhost
echo "$DATA" | grep litespeed_current_requests_per_vhost | while read -r line; do
    VHOST=$(echo "$line" | sed -n 's/.*vhost="\([^"]*\)".*/\1/p')
    VALUE=$(echo "$line" | grep -oE '[0-9]+(\.[0-9]+)?$')
    [[ -z "$VHOST" || -z "$VALUE" ]] && continue
    CLEAN_VHOST=$(echo "$VHOST" | sed 's/^APVH_//')
    echo "$CLEAN_VHOST conn $VALUE" >> "$TMP_FILE"
done

# ================= CALCULATE SCORES =================
# Calculate attack score for each vhost: Score = (req/sec * 2) + active connections
# Higher score indicates more suspicious traffic
while read -r VHOST; do
    REQ=$(grep "^$VHOST req" "$TMP_FILE" | awk '{print $3}' | head -n1)
    CONN=$(grep "^$VHOST conn" "$TMP_FILE" | awk '{print $3}' | head -n1)
    REQ=${REQ:-0}
    CONN=${CONN:-0}
    SCORE=$(echo "$REQ * 2 + $CONN" | bc)
    
    # Store only vhosts with traffic (score > 0)
    if (( $(echo "$REQ > 0" | bc -l) )) || (( CONN > 0 )); then
        echo "$SCORE|$VHOST|$REQ|$CONN" >> "$SORTED_FILE"
    fi
    
    # Check if thresholds are exceeded for alerting
    if (( $(echo "$REQ > $REQ_THRESHOLD" | bc -l) )) || (( CONN > CONN_THRESHOLD )); then
        echo "$VHOST|$REQ|$CONN|$SCORE" >> "$ALERT_FILE"
    fi
done < <(awk '{print $1}' "$TMP_FILE" | sort -u)

# ================= DISPLAY ALL VHOSTS (SORTED BY SCORE) =================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${WHITE}All Virtual Hosts Status (Sorted by Score - Highest First)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Sort in descending order by score (highest first)
sort -rn "$SORTED_FILE" | while IFS="|" read -r SCORE VHOST REQ CONN; do
    # Format numbers for display
    REQ_FORMATTED=$(printf "%.1f" $REQ)
    CONN_FORMATTED=$(printf "%.0f" $CONN)
    SCORE_FORMATTED=$(printf "%.1f" $SCORE)
    
    # Check if this vhost exceeds thresholds (suspicious)
    if (( $(echo "$REQ > $REQ_THRESHOLD" | bc -l) )) || (( CONN > CONN_THRESHOLD )); then
        echo -e "${RED}⚠${NC} ${WHITE}$VHOST${NC}"
        echo -e "   Req/sec: ${RED}$REQ_FORMATTED${NC}  |  Active Conn: ${RED}$CONN_FORMATTED${NC}  |  Score: ${RED}$SCORE_FORMATTED${NC}"
        echo ""
    else
        # Normal traffic
        echo -e "${GREEN}✓${NC} ${WHITE}$VHOST${NC}"
        echo -e "   Req/sec: ${GREEN}$REQ_FORMATTED${NC}  |  Active Conn: ${GREEN}$CONN_FORMATTED${NC}  |  Score: ${GREEN}$SCORE_FORMATTED${NC}"
        echo ""
    fi
done

# ================= SHOW ALERTS =================
# Display detailed alerts for vhosts exceeding thresholds
if [[ -s "$ALERT_FILE" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${RED}🚨 ALERTS - Suspicious Traffic Detected 🚨${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Sort alerts by score (highest first)
    sort -t'|' -k4 -rn "$ALERT_FILE" | while IFS="|" read -r VHOST REQ CONN SCORE; do
        REQ_FORMATTED=$(printf "%.1f" $REQ)
        CONN_FORMATTED=$(printf "%.0f" $CONN)
        SCORE_FORMATTED=$(printf "%.1f" $SCORE)
        
        echo -e "${RED}⚠⚠⚠ ATTACK DETECTED ⚠⚠⚠${NC}"
        echo -e "${WHITE}Virtual Host:${NC} ${RED}$VHOST${NC}"
        echo -e "${YELLOW}  • Requests per second:${NC} $REQ_FORMATTED"
        echo -e "${YELLOW}  • Active connections:${NC} $CONN_FORMATTED"
        echo -e "${YELLOW}  • Attack score:${NC} $SCORE_FORMATTED"
        
        # Determine severity level based on traffic volume
        if (( $(echo "$REQ > 50" | bc -l) )) || (( CONN > 200 )); then
            echo -e "${RED}  • SEVERITY: CRITICAL - Immediate action required${NC}"
        elif (( $(echo "$REQ > 30" | bc -l) )) || (( CONN > 100 )); then
            echo -e "${YELLOW}  • SEVERITY: HIGH - Investigate immediately${NC}"
        else
            echo -e "${BLUE}  • SEVERITY: MEDIUM - Monitor closely${NC}"
        fi
        echo ""
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${RED}⚠ Possible HTTP flood / DDoS attack detected${NC}"
    echo -e "${YELLOW}💡 Recommended actions:${NC}"
    echo -e "  1. Check access logs for suspicious patterns"
    echo -e "  2. Consider enabling rate limiting"
    echo -e "  3. Review firewall rules"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    EXIT_CODE=1
else
    # No alerts - system is healthy
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✓ SYSTEM STATUS: OKAY ✓${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}No suspicious traffic detected${NC}"
    echo -e "${CYAN}All metrics are within normal ranges${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    EXIT_CODE=0
fi

# ================= STATISTICS SUMMARY =================
echo ""
TOTAL_VHOSTS=$(wc -l < "$SORTED_FILE" 2>/dev/null || echo "0")
ALERT_COUNT=$(wc -l < "$ALERT_FILE" 2>/dev/null || echo "0")

# Calculate total score sum across all vhosts
TOTAL_SCORE=0
while IFS="|" read -r SCORE VHOST REQ CONN; do
    TOTAL_SCORE=$(echo "$TOTAL_SCORE + $SCORE" | bc)
done < "$SORTED_FILE"

# Find the highest score
HIGHEST_SCORE=$(sort -rn "$SORTED_FILE" 2>/dev/null | head -n1 | cut -d'|' -f1)
HIGHEST_SCORE=${HIGHEST_SCORE:-0}

echo -e "${WHITE}📊 Quick Stats:${NC}"
echo -e "  Total Active VHosts: ${CYAN}$TOTAL_VHOSTS${NC}"
echo -e "  Total Traffic Score: ${YELLOW}$TOTAL_SCORE${NC}"
echo -e "  Highest Score: ${RED}$HIGHEST_SCORE${NC}"
echo -e "  VHosts with alerts: ${RED}$ALERT_COUNT${NC}"
echo ""

# ================= TOP 5 BUSIEST VHOSTS =================
# Display top 5 vhosts with highest scores
echo -e "${WHITE}🏆 TOP 5 Busiest VHosts (by Score):${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -s "$SORTED_FILE" ]]; then
    head -n5 "$SORTED_FILE" | while IFS="|" read -r SCORE VHOST REQ CONN; do
        REQ_FORMATTED=$(printf "%.1f" $REQ)
        CONN_FORMATTED=$(printf "%.0f" $CONN)
        SCORE_FORMATTED=$(printf "%.1f" $SCORE)
        echo -e "  ${YELLOW}${SCORE_FORMATTED}${NC} - ${WHITE}$VHOST${NC} (req: $REQ_FORMATTED, conn: $CONN_FORMATTED)"
    done
else
    echo -e "  ${CYAN}No active traffic detected${NC}"
fi
echo ""

# ================= CLEANUP =================
# Remove temporary files
rm -f "$TMP_FILE" "$ALERT_FILE" "$SORTED_FILE"

exit $EXIT_CODE
