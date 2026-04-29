# ============================================
# Audit Unauthorized Access Report
# ============================================

echo "=== UNAUTHORIZED ACCESS AUDIT REPORT ==="
echo "Server: $(hostname)"
echo "Date: $(date)"
echo ""
echo "========================================="

# --- 1. Audit /var/log/wtmp ---
echo ""
echo "=== 1. ALL LOGIN ATTEMPTS (wtmp) ==="
echo "Last 50 logins:"
last -50

echo ""
echo "=== Failed SSH Attempts ==="
lastb -50 2>/dev/null || echo "No failed attempts log found"

echo ""
echo "=== SSH Logins by IP (last 30 days) ==="
last -i | awk '{print $3}' | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | head -20

echo ""
echo "=== Root Logins Only ==="
last root -20

echo ""
echo "=== Unusual Login Times (UTC midnight-5am) ==="
last -i | awk '{print $4,$5,$6,$7}' | grep -E "0[0-5]:[0-9]{2}" | head -20

# --- 2. Audit WHM Access Logs ---
echo ""
echo "=== 2. WHM ACCESS LOGS ==="

echo ""
echo "=== WHM Login Attempts (last 100) ==="
tail -100 /usr/local/cpanel/logs/access_log 2>/dev/null | grep -E "login|POST|dologin" || echo "No WHM access log found"

echo ""
echo "=== WHM Failed Logins ==="
grep -i "FAILED LOGIN\|failed" /usr/local/cpanel/logs/login_log 2>/dev/null | tail -30

echo ""
echo "=== WHM Login by IP ==="
grep -E "logged in|FAILED LOGIN" /usr/local/cpanel/logs/login_log 2>/dev/null | awk '{print $NF}' | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | head -20

echo ""
echo "=== WHM Access by IP (last 500 requests) ==="
tail -500 /usr/local/cpanel/logs/access_log 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -20

echo ""
echo "=== Suspicious IPs (multiple failed logins) ==="
grep "FAILED LOGIN" /usr/local/cpanel/logs/login_log 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/){print $i}}}' | sort | uniq -c | sort -rn | awk '$1 > 5' | head -20

# --- 3. cPanel User Access ---
echo ""
echo "=== 3. CPANEL USER ACCESS ==="

echo ""
echo "=== cPanel Login Log (last 50) ==="
tail -50 /usr/local/cpanel/logs/login_log 2>/dev/null | grep -v "FAILED"

echo ""
echo "=== Webmail Access ==="
grep -E "webmaild|webmail" /usr/local/cpanel/logs/access_log 2>/dev/null | tail -50 | awk '{print $1,$7}' | sort | uniq -c | sort -rn | head -20

# --- 4. Specific Suspicious Checks ---
echo ""
echo "=== 4. SUSPICIOUS ACTIVITY CHECKS ==="

echo ""
echo "=== cPanel API Calls (potential abuse) ==="
grep -E "create_user_session|passwd|FILEMANAGER|api2" /usr/local/cpanel/logs/access_log 2>/dev/null | tail -30

echo ""
echo "=== Unauthorized File Access Attempts ==="
grep -E "403|404|denied|forbidden" /var/log/messages 2>/dev/null | tail -20

echo ""
echo "=== SU Attempts ==="
grep "su:" /var/log/secure 2>/dev/null | tail -20

echo ""
echo "=== SUDO Attempts ==="
grep "sudo:" /var/log/secure 2>/dev/null | tail -20

# --- 5. Summary ---
echo ""
echo "========================================="
echo "=== SUMMARY ==="
echo "========================================="
echo ""
echo "Total unique IPs in wtmp: $(last -i | awk '{print $3}' | grep -E '[0-9]+\.' | sort -u | wc -l)"
echo "Failed WHM logins (7 days): $(grep "FAILED LOGIN" /usr/local/cpanel/logs/login_log 2>/dev/null | grep -c "$(date -d '7 days ago' +%Y-%m-%d)")"
echo "Total WHM access entries (24h): $(find /usr/local/cpanel/logs/access_log -mtime 0 2>/dev/null | wc -l)"
echo ""

# Save report
