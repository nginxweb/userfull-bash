#!/bin/bash

# ======================================================================
# MySQL/MariaDB Performance Analyzer - Universal Version with HTML Output
# Compatible with: MySQL 5.7, 8.0+ and MariaDB 10.x
# ======================================================================

# Color definitions for terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
RESET='\033[0m'
BG_RED='\033[41m'
BG_YELLOW='\033[43m'
BG_GREEN='\033[42m'
BG_BLUE='\033[44m'

# Configuration
OUTPUT_DIR="/var/www/html"
AUTH_USER="ultahost"
AUTH_PASS="ultadb"
HTML_FILE="${OUTPUT_DIR}/mysql_analyzer.html"  # Fixed filename
SERVER_HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
CURRENT_DATE=$(date '+%Y%m%d_%H%M%S')

# Create backup of previous report (optional)
if [ -f "$HTML_FILE" ]; then
    BACKUP_FILE="${OUTPUT_DIR}/mysql_analyzer_backup_${CURRENT_DATE}.html"
    cp "$HTML_FILE" "$BACKUP_FILE" 2>/dev/null
fi

# Header function for terminal
print_header() {
    echo -e "\n${BOLD}${WHITE}${BG_BLUE}════════════════════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${WHITE}${BG_BLUE}  $1${RESET}"
    echo -e "${BOLD}${WHITE}${BG_BLUE}════════════════════════════════════════════════════════════════════════════════${RESET}\n"
}

# Sub-header function for terminal
print_subheader() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${CYAN}  ► $1${RESET}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# MySQL wrapper - completely suppress all warnings and errors to stderr
mysql_exec() {
    mysql "$@" 2>/dev/null
}

# Function to test MySQL connection
test_mysql_connection() {
    local cmd="$1"
    if eval "$cmd -e 'SELECT 1'" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# HTML generation functions
html_start() {
    cat > "$HTML_FILE" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="300"> <!-- Auto-refresh every 5 minutes -->
    <title>MySQL/MariaDB Performance Analyzer - Live Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', 'Roboto', 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            min-height: 100vh;
            padding: 20px;
            color: #e0e0e0;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: rgba(26, 26, 46, 0.95);
            border-radius: 20px;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
            overflow: hidden;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        
        .header {
            background: linear-gradient(135deg, #e94560 0%, #c62a47 100%);
            padding: 30px 40px;
            border-bottom: 3px solid #ff6b6b;
        }
        
        .header h1 {
            font-size: 2.2rem;
            font-weight: 700;
            color: white;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
            margin-bottom: 10px;
        }
        
        .header .subtitle {
            font-size: 1rem;
            color: rgba(255,255,255,0.9);
            display: flex;
            gap: 30px;
            flex-wrap: wrap;
        }
        
        .live-badge {
            background: #28a745;
            color: white;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 1px;
            display: inline-block;
            margin-left: 15px;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.7; }
            100% { opacity: 1; }
        }
        
        .content {
            padding: 30px 40px;
        }
        
        .section {
            margin-bottom: 40px;
            background: rgba(255, 255, 255, 0.03);
            border-radius: 15px;
            padding: 25px;
            border: 1px solid rgba(255, 255, 255, 0.05);
        }
        
        .section-title {
            font-size: 1.5rem;
            font-weight: 600;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #e94560;
            color: #e94560;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .section-title i {
            font-size: 1.3rem;
        }
        
        .subsection-title {
            font-size: 1.2rem;
            font-weight: 500;
            margin: 20px 0 15px 0;
            color: #00d2ff;
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .info-card {
            background: rgba(0, 0, 0, 0.3);
            padding: 15px 20px;
            border-radius: 10px;
            border-left: 4px solid #e94560;
        }
        
        .info-card .label {
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: #888;
            margin-bottom: 5px;
        }
        
        .info-card .value {
            font-size: 1.3rem;
            font-weight: 600;
            color: #fff;
        }
        
        .info-card .value.highlight {
            color: #e94560;
        }
        
        .info-card .value.warning {
            color: #ffc107;
        }
        
        .info-card .value.success {
            color: #28a745;
        }
        
        pre {
            background: #0d1117;
            color: #e6edf3;
            padding: 20px;
            border-radius: 10px;
            overflow-x: auto;
            font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'Consolas', monospace;
            font-size: 0.9rem;
            line-height: 1.5;
            border: 1px solid #30363d;
            margin: 15px 0;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 10px;
            overflow: hidden;
        }
        
        th {
            background: #e94560;
            color: white;
            padding: 12px 15px;
            text-align: left;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.85rem;
            letter-spacing: 0.5px;
        }
        
        td {
            padding: 10px 15px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        }
        
        tr:hover {
            background: rgba(233, 69, 96, 0.1);
        }
        
        .badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: 600;
        }
        
        .badge-danger {
            background: rgba(220, 53, 69, 0.2);
            color: #dc3545;
            border: 1px solid #dc3545;
        }
        
        .badge-warning {
            background: rgba(255, 193, 7, 0.2);
            color: #ffc107;
            border: 1px solid #ffc107;
        }
        
        .badge-success {
            background: rgba(40, 167, 69, 0.2);
            color: #28a745;
            border: 1px solid #28a745;
        }
        
        .badge-info {
            background: rgba(0, 210, 255, 0.2);
            color: #00d2ff;
            border: 1px solid #00d2ff;
        }
        
        .recommendation {
            background: linear-gradient(135deg, rgba(233, 69, 96, 0.1) 0%, rgba(198, 42, 71, 0.1) 100%);
            padding: 20px;
            border-radius: 10px;
            margin: 15px 0;
            border-left: 4px solid #e94560;
        }
        
        .recommendation-item {
            padding: 10px 0;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
        }
        
        .recommendation-item:last-child {
            border-bottom: none;
        }
        
        .recommendation-item .icon {
            display: inline-block;
            width: 25px;
            color: #ffc107;
        }
        
        .recommendation-item .text {
            color: #e0e0e0;
        }
        
        .recommendation-item .solution {
            margin-left: 30px;
            color: #00d2ff;
            font-family: monospace;
            font-size: 0.9rem;
        }
        
        .footer {
            background: rgba(0, 0, 0, 0.3);
            padding: 20px 40px;
            text-align: center;
            color: #888;
            font-size: 0.9rem;
            border-top: 1px solid rgba(255, 255, 255, 0.05);
        }
        
        .metric-high {
            color: #dc3545;
        }
        
        .metric-medium {
            color: #ffc107;
        }
        
        .metric-good {
            color: #28a745;
        }
        
        @media (max-width: 768px) {
            .header { padding: 20px; }
            .content { padding: 20px; }
            .section { padding: 15px; }
            .header h1 { font-size: 1.5rem; }
            .info-grid { grid-template-columns: 1fr; }
            table { font-size: 0.8rem; }
            th, td { padding: 8px 10px; }
        }
        
        .scrollable {
            max-height: 400px;
            overflow-y: auto;
        }
        
        .query-preview {
            font-family: 'JetBrains Mono', monospace;
            background: #1e1e1e;
            color: #ce9178;
            padding: 2px 5px;
            border-radius: 4px;
        }
        
        .last-updated {
            color: #888;
            font-size: 0.9rem;
            margin-top: 10px;
            text-align: right;
        }
    </style>
</head>
<body>
    <div class="container">
HTMLEOF
}

html_header_content() {
    cat >> "$HTML_FILE" << HTMLEOF
        <div class="header">
            <h1>🐬 MySQL/MariaDB Performance Analyzer <span class="live-badge">● LIVE</span></h1>
            <div class="subtitle">
                <span>🖥️ Server: ${SERVER_HOSTNAME}</span>
                <span>📅 Last Updated: ${TIMESTAMP}</span>
                <span>🔧 Version: ${MYSQL_VER}</span>
                <span>📊 Variant: $([ "$IS_MARIADB" = true ] && echo "MariaDB" || echo "MySQL")</span>
            </div>
        </div>
        <div class="content">
HTMLEOF
}

html_section_start() {
    local title="$1"
    local icon="$2"
    cat >> "$HTML_FILE" << HTMLEOF
            <div class="section">
                <div class="section-title">
                    <span>${icon}</span>
                    <span>${title}</span>
                </div>
HTMLEOF
}

html_section_end() {
    echo "            </div>" >> "$HTML_FILE"
}

html_subsection() {
    local title="$1"
    echo "                <div class=\"subsection-title\">▸ ${title}</div>" >> "$HTML_FILE"
}

html_info_card() {
    local label="$1"
    local value="$2"
    local class="${3:-}"
    echo "                    <div class=\"info-card\">" >> "$HTML_FILE"
    echo "                        <div class=\"label\">${label}</div>" >> "$HTML_FILE"
    echo "                        <div class=\"value ${class}\">${value}</div>" >> "$HTML_FILE"
    echo "                    </div>" >> "$HTML_FILE"
}

html_info_grid_start() {
    echo "                <div class=\"info-grid\">" >> "$HTML_FILE"
}

html_info_grid_end() {
    echo "                </div>" >> "$HTML_FILE"
}

html_pre() {
    local content="$1"
    echo "                <pre>${content}</pre>" >> "$HTML_FILE"
}

html_end() {
    cat >> "$HTML_FILE" << HTMLEOF
        </div>
        <div class="footer">
            <div>MySQL Performance Analyzer v1.0 | Server: ${SERVER_HOSTNAME}</div>
            <div class="last-updated">Last Updated: ${TIMESTAMP} | Report refreshes automatically every 5 minutes</div>
        </div>
    </div>
</body>
</html>
HTMLEOF
}

# Function to escape HTML special characters
escape_html() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

# Create .htaccess file for authentication
create_htaccess() {
    local htaccess_file="${OUTPUT_DIR}/.htaccess"
    local htpasswd_file="${OUTPUT_DIR}/.htpasswd"
    
    # Create .htpasswd file
    if command -v htpasswd &>/dev/null; then
        htpasswd -cb "$htpasswd_file" "$AUTH_USER" "$AUTH_PASS" 2>/dev/null
    else
        # Fallback: create simple .htpasswd with openssl
        if command -v openssl &>/dev/null; then
            local pass_hash=$(echo -n "$AUTH_PASS" | openssl passwd -apr1 -stdin)
            echo "${AUTH_USER}:${pass_hash}" > "$htpasswd_file"
        fi
    fi
    
    # Create/update .htaccess
    cat > "$htaccess_file" << HTACCESS
# MySQL Analyzer Protection
<FilesMatch "mysql_analyzer.*\.html$">
    AuthType Basic
    AuthName "MySQL Analyzer Reports - Restricted Access"
    AuthUserFile ${htpasswd_file}
    Require valid-user
</FilesMatch>

# Prevent directory listing
Options -Indexes
HTACCESS
    
    # Set proper permissions
    chmod 644 "$htaccess_file" 2>/dev/null
    chmod 644 "$htpasswd_file" 2>/dev/null
}

# Detect MySQL/MariaDB socket
detect_socket() {
    local socket_paths=(
        "/var/lib/mysql/mysql.sock"
        "/tmp/mysql.sock"
        "/var/run/mysqld/mysqld.sock"
        "/var/run/mariadb/mariadb.sock"
        "/var/lib/mysql/mariadb.sock"
        "/run/mysqld/mysqld.sock"
        "/run/mariadb/mariadb.sock"
        "/var/lib/mysql/mysqld.sock"
    )
    
    for sock in "${socket_paths[@]}"; do
        if [ -S "$sock" ]; then
            echo "$sock"
            return 0
        fi
    done
    
    # Try to find from my.cnf
    if [ -f "/etc/my.cnf" ]; then
        local cnf_socket=$(grep -E "^socket\s*=" /etc/my.cnf | head -1 | awk -F'=' '{print $2}' | xargs)
        if [ -n "$cnf_socket" ] && [ -S "$cnf_socket" ]; then
            echo "$cnf_socket"
            return 0
        fi
    fi
    
    # Try to find from my.cnf.d
    if [ -d "/etc/my.cnf.d" ]; then
        local cnf_socket=$(grep -h -E "^socket\s*=" /etc/my.cnf.d/*.cnf 2>/dev/null | head -1 | awk -F'=' '{print $2}' | xargs)
        if [ -n "$cnf_socket" ] && [ -S "$cnf_socket" ]; then
            echo "$cnf_socket"
            return 0
        fi
    fi
    
    return 1
}

# Try to get MySQL credentials from various sources
MYSQL_USER="root"
MYSQL_PASS=""
MYSQL_SOCKET=$(detect_socket)

# Try to get password from /root/.my.cnf
if [ -f "/root/.my.cnf" ]; then
    MYSQL_PASS=$(grep password /root/.my.cnf | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
fi

# Try multiple connection methods
CONNECTION_SUCCESS=false
CONNECTION_METHOD=""

# Method 1: Socket with no password (most common for cPanel/CloudLinux)
if [ -n "$MYSQL_SOCKET" ]; then
    MYSQL_CMD="mysql_exec -u${MYSQL_USER} -S $MYSQL_SOCKET"
    if test_mysql_connection "$MYSQL_CMD"; then
        CONNECTION_SUCCESS=true
        CONNECTION_METHOD="Socket (no password)"
    fi
fi

# Method 2: Socket with password (if found in .my.cnf)
if [ "$CONNECTION_SUCCESS" = false ] && [ -n "$MYSQL_SOCKET" ] && [ -n "$MYSQL_PASS" ]; then
    MYSQL_CMD="mysql_exec -u${MYSQL_USER} -p${MYSQL_PASS} -S $MYSQL_SOCKET"
    if test_mysql_connection "$MYSQL_CMD"; then
        CONNECTION_SUCCESS=true
        CONNECTION_METHOD="Socket (with password)"
    fi
fi

# Method 3: TCP/IP with no password (localhost)
if [ "$CONNECTION_SUCCESS" = false ]; then
    MYSQL_CMD="mysql_exec -u${MYSQL_USER} -h 127.0.0.1"
    if test_mysql_connection "$MYSQL_CMD"; then
        CONNECTION_SUCCESS=true
        CONNECTION_METHOD="TCP/IP (no password)"
    fi
fi

# Method 4: TCP/IP with password
if [ "$CONNECTION_SUCCESS" = false ] && [ -n "$MYSQL_PASS" ]; then
    MYSQL_CMD="mysql_exec -u${MYSQL_USER} -p${MYSQL_PASS} -h 127.0.0.1"
    if test_mysql_connection "$MYSQL_CMD"; then
        CONNECTION_SUCCESS=true
        CONNECTION_METHOD="TCP/IP (with password)"
    fi
fi

# Method 5: Try using sudo mysql (if running as root)
if [ "$CONNECTION_SUCCESS" = false ] && [ "$EUID" -eq 0 ]; then
    if command -v sudo &>/dev/null; then
        if sudo mysql -e "SELECT 1" &>/dev/null; then
            mysql_exec() {
                sudo mysql "$@" 2>/dev/null
            }
            MYSQL_CMD="mysql_exec"
            CONNECTION_SUCCESS=true
            CONNECTION_METHOD="Sudo MySQL"
        fi
    fi
fi

# If all methods fail, exit
if [ "$CONNECTION_SUCCESS" = false ]; then
    echo -e "${RED}${BOLD}ERROR: Cannot connect to MySQL/MariaDB server!${RESET}"
    exit 1
fi

# Detect MySQL version and variant
MYSQL_VER=$(eval "$MYSQL_CMD -e 'SELECT VERSION();' -s -N")
IS_MYSQL=false
IS_MARIADB=false
IS_MYSQL_8=false

if echo "$MYSQL_VER" | grep -qi "mariadb"; then
    IS_MARIADB=true
elif echo "$MYSQL_VER" | grep -q "^8\."; then
    IS_MYSQL_8=true
    IS_MYSQL=true
elif echo "$MYSQL_VER" | grep -q "^5\."; then
    IS_MYSQL=true
fi

# Check if performance_schema is enabled
PFS_ENABLED=$(eval "$MYSQL_CMD -e 'SHOW VARIABLES LIKE \"performance_schema\";' -s -N" 2>/dev/null | awk '{print $2}')

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR" 2>/dev/null

# Start HTML generation
html_start
html_header_content

# Clear terminal and show header
clear
echo -e "${BOLD}${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║     MySQL/MariaDB Performance Analyzer for cPanel Servers        ║"
echo "║                     Generated: ${TIMESTAMP}                    ║"
echo "║           Compatible with MySQL 5.7/8.0+ and MariaDB             ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "${CYAN}📄 HTML Report will be saved to: ${YELLOW}${HTML_FILE}${RESET}\n"

# Helper function to get status value
get_status() {
    eval "$MYSQL_CMD -e \"SHOW GLOBAL STATUS LIKE '$1';\" -s -N" | awk '{print $2}'
}

# Helper function to get variable value
get_variable() {
    eval "$MYSQL_CMD -e \"SHOW VARIABLES LIKE '$1';\" -s -N" | awk '{print $2}'
}

# ======================================================================
# 1. SERVER INFORMATION
# ======================================================================
print_header "📊 SERVER INFORMATION"
html_section_start "📊 SERVER INFORMATION" "🖥️"

OS_VERSION=$(cat /etc/redhat-release 2>/dev/null || echo "N/A")
KERNEL=$(uname -r)
UPTIME_SYS=$(uptime | awk -F'up' '{print $2}' | cut -d',' -f1 | xargs)

echo -e "${BOLD}${GREEN}► Server Hostname:${RESET} ${SERVER_HOSTNAME}"
echo -e "${BOLD}${GREEN}► OS Version:${RESET} ${OS_VERSION}"
echo -e "${BOLD}${GREEN}► Kernel:${RESET} ${KERNEL}"
echo -e "${BOLD}${GREEN}► Uptime:${RESET} ${UPTIME_SYS}"

html_subsection "System Information"
html_info_grid_start
html_info_card "Server Hostname" "${SERVER_HOSTNAME}"
html_info_card "OS Version" "${OS_VERSION}"
html_info_card "Kernel" "${KERNEL}"
html_info_card "Uptime" "${UPTIME_SYS}"
html_info_card "MySQL Version" "${MYSQL_VER}"
html_info_card "Variant" "$([ "$IS_MARIADB" = true ] && echo "MariaDB" || echo "MySQL")"
html_info_card "Connection Method" "${CONNECTION_METHOD}"
html_info_grid_end

# CloudLinux detection
if [ -f "/etc/cloudlinux-release" ]; then
    CL_INFO=$(cat /etc/cloudlinux-release)
    echo -e "${BOLD}${GREEN}► CloudLinux:${RESET} ${CL_INFO}"
fi

html_section_end

# ======================================================================
# 2. GLOBAL STATUS
# ======================================================================
print_header "📈 GLOBAL STATUS & METRICS"
html_section_start "📈 GLOBAL STATUS & METRICS" "📊"

print_subheader "Connection Statistics"
html_subsection "Connection Statistics"

THREADS_CONNECTED=$(get_status "Threads_connected")
THREADS_RUNNING=$(get_status "Threads_running")
MAX_USED_CONN=$(get_status "Max_used_connections")
ABORTED_CLIENTS=$(get_status "Aborted_clients")
ABORTED_CONNECTS=$(get_status "Aborted_connects")
CONNECTIONS=$(get_status "Connections")
MAX_CONN=$(get_variable "max_connections")

echo -e "${BOLD}Threads connected:${RESET} ${GREEN}${THREADS_CONNECTED}${RESET}"
echo -e "${BOLD}Threads running:${RESET} ${YELLOW}${THREADS_RUNNING}${RESET}"
echo -e "${BOLD}Max used connections:${RESET} ${MAX_USED_CONN} ($(echo "scale=1; $MAX_USED_CONN * 100 / $MAX_CONN" | bc 2>/dev/null || echo "N/A")% of limit)"
echo -e "${BOLD}Total connections:${RESET} ${CONNECTIONS}"
echo -e "${BOLD}Aborted clients:${RESET} ${ABORTED_CLIENTS} $([ "$ABORTED_CLIENTS" -gt 10000 ] && echo -e "${RED}⚠️ HIGH${RESET}")"
echo -e "${BOLD}Aborted connects:${RESET} ${ABORTED_CONNECTS} $([ "$ABORTED_CONNECTS" -gt 1000 ] && echo -e "${RED}⚠️ HIGH${RESET}")"
echo -e "${BOLD}Connection Limit:${RESET} ${MAX_CONN}"

html_info_grid_start
html_info_card "Threads Connected" "${THREADS_CONNECTED}" "success"
html_info_card "Threads Running" "${THREADS_RUNNING}" "$([ "$THREADS_RUNNING" -gt 10 ] && echo "warning" || echo "success")"
html_info_card "Max Used Connections" "${MAX_USED_CONN}"
html_info_card "Total Connections" "${CONNECTIONS}"
html_info_card "Aborted Clients" "${ABORTED_CLIENTS}" "$([ "$ABORTED_CLIENTS" -gt 10000 ] && echo "highlight" || echo "")"
html_info_card "Aborted Connects" "${ABORTED_CONNECTS}" "$([ "$ABORTED_CONNECTS" -gt 1000 ] && echo "highlight" || echo "")"
html_info_card "Connection Limit" "${MAX_CONN}"
html_info_grid_end

print_subheader "Query Statistics"
html_subsection "Query Statistics"

QUESTIONS=$(get_status "Questions")
QUERIES=$(get_status "Queries")
SLOW_QUERIES=$(get_status "Slow_queries")
SELECT_FULL_JOIN=$(get_status "Select_full_join")
SELECT_RANGE_CHECK=$(get_status "Select_range_check")
SORT_MERGE_PASSES=$(get_status "Sort_merge_passes")
UPTIME=$(get_status "Uptime")

if [ -n "$QUESTIONS" ] && [ -n "$UPTIME" ] && [ "$UPTIME" -gt 0 ]; then
    QPS=$(echo "scale=1; $QUESTIONS / $UPTIME" | bc 2>/dev/null)
else
    QPS="N/A"
fi

echo -e "${BOLD}Questions:${RESET} ${QUESTIONS} (${QPS} qps)"
echo -e "${BOLD}Queries:${RESET} ${QUERIES}"
echo -e "${BOLD}Slow queries:${RESET} ${SLOW_QUERIES} $([ "$SLOW_QUERIES" -gt 100 ] && echo -e "${RED}⚠️ HIGH${RESET}")"
echo -e "${BOLD}Select full join:${RESET} ${SELECT_FULL_JOIN}"
echo -e "${BOLD}Sort merge passes:${RESET} ${SORT_MERGE_PASSES}"

html_info_grid_start
html_info_card "Questions" "${QUESTIONS}"
html_info_card "QPS" "${QPS}"
html_info_card "Queries" "${QUERIES}"
html_info_card "Slow Queries" "${SLOW_QUERIES}" "$([ "$SLOW_QUERIES" -gt 100 ] && echo "highlight" || echo "")"
html_info_card "Select Full Join" "${SELECT_FULL_JOIN}" "$([ "$SELECT_FULL_JOIN" -gt 10000 ] && echo "warning" || echo "")"
html_info_card "Sort Merge Passes" "${SORT_MERGE_PASSES}"
html_info_grid_end

html_section_end

# ======================================================================
# 3. INNODB METRICS
# ======================================================================
print_header "🗄️  INNODB ENGINE METRICS"
html_section_start "🗄️  INNODB ENGINE METRICS" "🗄️"

INNODB_STATUS=$(eval "$MYSQL_CMD -e 'SHOW ENGINE INNODB STATUS\\G'")

IB_POOL_READS=$(get_status "Innodb_buffer_pool_reads")
IB_POOL_READ_REQUESTS=$(get_status "Innodb_buffer_pool_read_requests")
IB_POOL_SIZE=$(get_variable "innodb_buffer_pool_size")
IB_POOL_PAGES_DATA=$(get_status "Innodb_buffer_pool_pages_data")
IB_POOL_PAGES_DIRTY=$(get_status "Innodb_buffer_pool_pages_dirty")
IB_POOL_PAGES_FREE=$(get_status "Innodb_buffer_pool_pages_free")
IB_POOL_PAGES_TOTAL=$(get_status "Innodb_buffer_pool_pages_total")
IB_POOL_WAIT_FREE=$(get_status "Innodb_buffer_pool_wait_free")

if [ -n "$IB_POOL_SIZE" ]; then
    POOL_GB=$(echo "scale=2; $IB_POOL_SIZE / 1024 / 1024 / 1024" | bc 2>/dev/null)
    echo -e "${BOLD}Buffer Pool Size:${RESET} ${POOL_GB} GB"
fi

if [ -n "$IB_POOL_PAGES_TOTAL" ] && [ -n "$IB_POOL_PAGES_DATA" ]; then
    DATA_PCT=$(echo "scale=1; $IB_POOL_PAGES_DATA * 100 / $IB_POOL_PAGES_TOTAL" | bc 2>/dev/null)
    echo -e "${BOLD}Buffer Pool Usage:${RESET} Data: ${DATA_PCT}% | Dirty: ${IB_POOL_PAGES_DIRTY:-0} pages"
fi

if [ -n "$IB_POOL_READ_REQUESTS" ] && [ -n "$IB_POOL_READS" ] && [ "$IB_POOL_READ_REQUESTS" -gt 0 ]; then
    BP_HIT_RATIO=$(echo "scale=2; (1 - $IB_POOL_READS / $IB_POOL_READ_REQUESTS) * 100" | bc 2>/dev/null)
    if [ -n "$BP_HIT_RATIO" ]; then
        if (( $(echo "$BP_HIT_RATIO < 95" | bc -l) )); then
            echo -e "${YELLOW}⚠️  Buffer Pool Hit Ratio: ${BP_HIT_RATIO}% (Below 95%)${RESET}"
        else
            echo -e "${GREEN}✓ Buffer Pool Hit Ratio: ${BP_HIT_RATIO}%${RESET}"
        fi
    fi
fi

html_info_grid_start
[ -n "$POOL_GB" ] && html_info_card "Buffer Pool Size" "${POOL_GB} GB"
[ -n "$DATA_PCT" ] && html_info_card "Buffer Pool Usage" "${DATA_PCT}%"
[ -n "$BP_HIT_RATIO" ] && html_info_card "Buffer Pool Hit Ratio" "${BP_HIT_RATIO}%" "$([ $(echo "$BP_HIT_RATIO < 95" | bc -l) -eq 1 ] && echo "warning" || echo "success")"
html_info_card "Dirty Pages" "${IB_POOL_PAGES_DIRTY:-0}"
html_info_grid_end

IB_READS=$(get_status "Innodb_data_reads")
IB_WRITES=$(get_status "Innodb_data_writes")
IB_FSYNCS=$(get_status "Innodb_data_fsyncs")
IB_ROW_LOCK_WAITS=$(get_status "Innodb_row_lock_waits")
IB_ROW_LOCK_TIME=$(get_status "Innodb_row_lock_time")

echo -e "\n${BOLD}InnoDB I/O:${RESET}"
echo -e "  Reads: ${IB_READS} | Writes: ${IB_WRITES} | Fsyncs: ${IB_FSYNCS}"
echo -e "  Row Lock Waits: ${IB_ROW_LOCK_WAITS} | Lock Wait Time: ${IB_ROW_LOCK_TIME} ms"

html_subsection "InnoDB I/O Statistics"
html_info_grid_start
html_info_card "Data Reads" "${IB_READS}"
html_info_card "Data Writes" "${IB_WRITES}"
html_info_card "Fsyncs" "${IB_FSYNCS}"
html_info_card "Row Lock Waits" "${IB_ROW_LOCK_WAITS}"
html_info_card "Lock Wait Time" "${IB_ROW_LOCK_TIME} ms"
html_info_grid_end

html_section_end

# ======================================================================
# 4. CURRENT PROCESSLIST
# ======================================================================
print_header "🔄 ACTIVE DATABASE CONNECTIONS & QUERIES"
html_section_start "🔄 ACTIVE DATABASE CONNECTIONS & QUERIES" "🔄"

TOTAL_COUNT=$(eval "$MYSQL_CMD -e 'SELECT COUNT(*) FROM information_schema.PROCESSLIST;' -s -N")
ACTIVE_COUNT=$(eval "$MYSQL_CMD -e \"SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE COMMAND != 'Sleep' AND USER != 'system user';\" -s -N")

echo -e "${BOLD}Total Connections: ${WHITE}${TOTAL_COUNT}${RESET} | ${BOLD}Active Queries: ${YELLOW}${ACTIVE_COUNT}${RESET}\n"
html_info_grid_start
html_info_card "Total Connections" "${TOTAL_COUNT}"
html_info_card "Active Queries" "${ACTIVE_COUNT}" "$([ "$ACTIVE_COUNT" -gt 10 ] && echo "warning" || echo "success")"
html_info_grid_end

echo -e "\n${BOLD}${CYAN}Active Queries (Running/Locked):${RESET}"
html_subsection "Active Queries"

ACTIVE_QUERIES=$(eval "$MYSQL_CMD -e \"
SELECT 
    ID,
    USER,
    IFNULL(DB, 'NULL') as DB,
    COMMAND,
    TIME,
    IFNULL(STATE, 'N/A') as STATE,
    SUBSTRING(INFO, 1, 100) as QUERY_PREVIEW
FROM information_schema.PROCESSLIST 
WHERE COMMAND != 'Sleep' 
  AND USER NOT IN ('system user', 'event_scheduler')
  AND INFO IS NOT NULL
ORDER BY TIME DESC
LIMIT 20;\" 2>/dev/null")

echo "$ACTIVE_QUERIES" | column -t -s $'\t'
echo "<pre>$(escape_html "$ACTIVE_QUERIES")</pre>" >> "$HTML_FILE"

LOCKED_QUERIES=$(eval "$MYSQL_CMD -e \"
SELECT 
    ID,
    USER,
    IFNULL(DB, 'NULL') as DB,
    TIME,
    IFNULL(STATE, 'N/A') as STATE,
    SUBSTRING(INFO, 1, 100) as QUERY_PREVIEW
FROM information_schema.PROCESSLIST 
WHERE STATE LIKE '%lock%' 
   OR STATE LIKE '%wait%'
   OR COMMAND = 'Locked'
ORDER BY TIME DESC;\" 2>/dev/null")

if [ -n "$LOCKED_QUERIES" ]; then
    echo -e "\n${BOLD}${RED}Locked/Waiting Queries:${RESET}"
    echo "$LOCKED_QUERIES" | column -t -s $'\t'
    html_subsection "Locked/Waiting Queries"
    echo "<pre>$(escape_html "$LOCKED_QUERIES")</pre>" >> "$HTML_FILE"
fi

html_section_end

# ======================================================================
# 5. CONNECTION SUMMARY BY DATABASE
# ======================================================================
print_header "📊 CONNECTION SUMMARY BY DATABASE"
html_section_start "📊 CONNECTION SUMMARY BY DATABASE" "📊"

DB_CONNECTIONS=$(eval "$MYSQL_CMD -e \"
SELECT 
    IFNULL(DB, 'NULL') as 'DATABASE',
    COUNT(*) as CONNECTIONS,
    SUM(CASE WHEN COMMAND != 'Sleep' THEN 1 ELSE 0 END) as ACTIVE_QUERIES,
    MAX(TIME) as MAX_QUERY_TIME_SEC
FROM information_schema.PROCESSLIST 
WHERE USER NOT IN ('system user', 'event_scheduler')
GROUP BY DB 
ORDER BY COUNT(*) DESC, ACTIVE_QUERIES DESC
LIMIT 15;\" 2>/dev/null")

echo -e "${BOLD}Connections per Database:${RESET}"
echo "$DB_CONNECTIONS" | column -t -s $'\t'
html_subsection "Connections per Database"
echo "<pre>$(escape_html "$DB_CONNECTIONS")</pre>" >> "$HTML_FILE"

USER_CONNECTIONS=$(eval "$MYSQL_CMD -e \"
SELECT 
    USER,
    COUNT(*) as CONNECTIONS,
    SUM(CASE WHEN COMMAND != 'Sleep' THEN 1 ELSE 0 END) as ACTIVE_QUERIES
FROM information_schema.PROCESSLIST 
WHERE USER NOT IN ('system user', 'event_scheduler')
GROUP BY USER 
ORDER BY COUNT(*) DESC
LIMIT 15;\" 2>/dev/null")

echo -e "\n${BOLD}Connections per User:${RESET}"
echo "$USER_CONNECTIONS" | column -t -s $'\t'
html_subsection "Connections per User"
echo "<pre>$(escape_html "$USER_CONNECTIONS")</pre>" >> "$HTML_FILE"

html_section_end

# ======================================================================
# 6. SLOW QUERIES ANALYSIS
# ======================================================================
print_header "🐌 SLOW QUERIES ANALYSIS"
html_section_start "🐌 SLOW QUERIES ANALYSIS" "🐌"

SLOW_LOG=$(get_variable "slow_query_log")
SLOW_FILE=$(get_variable "slow_query_log_file")
LONG_QUERY_TIME=$(get_variable "long_query_time")

echo -e "${BOLD}Slow Query Log Status:${RESET} ${SLOW_LOG}"
echo -e "${BOLD}Slow Query Log File:${RESET} ${SLOW_FILE}"
echo -e "${BOLD}Long Query Time Threshold:${RESET} ${LONG_QUERY_TIME} seconds"

html_info_grid_start
html_info_card "Slow Query Log" "${SLOW_LOG}"
html_info_card "Log File" "${SLOW_FILE}"
html_info_card "Threshold" "${LONG_QUERY_TIME} seconds"
html_info_grid_end

if [ "$PFS_ENABLED" != "OFF" ]; then
    HAS_DIGEST=$(eval "$MYSQL_CMD -e \"SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='performance_schema' AND TABLE_NAME='events_statements_summary_by_digest';\" -s -N")
    
    if [ "$HAS_DIGEST" = "1" ]; then
        SLOW_PATTERNS=$(eval "$MYSQL_CMD -e \"
        SELECT 
            LEFT(DIGEST_TEXT, 150) as QUERY_PATTERN,
            COUNT_STAR as EXEC_COUNT,
            ROUND(AVG_TIMER_WAIT/1000000000000, 2) as AVG_TIME_SEC,
            ROUND(MAX_TIMER_WAIT/1000000000000, 2) as MAX_TIME_SEC
        FROM performance_schema.events_statements_summary_by_digest
        WHERE DIGEST_TEXT IS NOT NULL
          AND SCHEMA_NAME NOT IN ('performance_schema', 'information_schema', 'mysql', 'sys')
        ORDER BY AVG_TIMER_WAIT DESC
        LIMIT 10\\G\" 2>/dev/null" | grep -E "QUERY_PATTERN:|EXEC_COUNT:|AVG_TIME_SEC:|MAX_TIME_SEC:" | sed 's/^[ \t]*//')
        
        if [ -n "$SLOW_PATTERNS" ]; then
            echo -e "\n${BOLD}${YELLOW}Top 10 Slowest Query Patterns:${RESET}"
            echo "$SLOW_PATTERNS"
            html_subsection "Top 10 Slowest Query Patterns"
            echo "<pre>$(escape_html "$SLOW_PATTERNS")</pre>" >> "$HTML_FILE"
        fi
    fi
fi

html_section_end

# ======================================================================
# 7. TABLE STATISTICS
# ======================================================================
print_header "📋 TABLE STATISTICS"
html_section_start "📋 TABLE STATISTICS" "📋"

DB_SIZES=$(eval "$MYSQL_CMD -e \"
SELECT 
    table_schema as 'DATABASE',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as SIZE_MB,
    COUNT(*) as TABLES
FROM information_schema.TABLES 
WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
GROUP BY table_schema
ORDER BY SUM(data_length + index_length) DESC
LIMIT 10;\" 2>/dev/null")

echo -e "${BOLD}Top 10 Databases by Size:${RESET}"
echo "$DB_SIZES" | column -t -s $'\t'
html_subsection "Top 10 Databases by Size"
echo "<pre>$(escape_html "$DB_SIZES")</pre>" >> "$HTML_FILE"

LARGE_TABLES=$(eval "$MYSQL_CMD -e \"
SELECT 
    CONCAT(table_schema, '.', table_name) as TABLE_NAME,
    ROUND((data_length + index_length) / 1024 / 1024, 2) as TOTAL_MB,
    table_rows as 'ROWS',
    ENGINE
FROM information_schema.TABLES 
WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
ORDER BY (data_length + index_length) DESC
LIMIT 15;\" 2>/dev/null")

echo -e "\n${BOLD}Top 10 Largest Tables:${RESET}"
echo "$LARGE_TABLES" | column -t -s $'\t'
html_subsection "Top 15 Largest Tables"
echo "<pre>$(escape_html "$LARGE_TABLES")</pre>" >> "$HTML_FILE"

NO_PK_TABLES=$(eval "$MYSQL_CMD -e \"
SELECT 
    CONCAT(t.table_schema, '.', t.table_name) as TABLE_NAME,
    t.ENGINE,
    ROUND((t.data_length + t.index_length) / 1024 / 1024, 2) as SIZE_MB
FROM information_schema.TABLES t
LEFT JOIN information_schema.STATISTICS s 
    ON t.table_schema = s.table_schema 
    AND t.table_name = s.table_name 
    AND s.index_name = 'PRIMARY'
WHERE t.table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
  AND t.table_type = 'BASE TABLE'
  AND s.index_name IS NULL
ORDER BY (t.data_length + t.index_length) DESC
LIMIT 10;\" 2>/dev/null")

echo -e "\n${BOLD}Tables Without Primary Key:${RESET}"
echo "$NO_PK_TABLES" | column -t -s $'\t'
html_subsection "Tables Without Primary Key"
echo "<pre>$(escape_html "$NO_PK_TABLES")</pre>" >> "$HTML_FILE"

html_section_end

# ======================================================================
# 8. MYISAM STATUS
# ======================================================================
MYISAM_COUNT=$(eval "$MYSQL_CMD -e \"SELECT COUNT(*) FROM information_schema.TABLES WHERE ENGINE='MyISAM' AND table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys');\" -s -N 2>/dev/null")
if [ "$MYISAM_COUNT" -gt 0 ]; then
    print_header "⚠️  MYISAM TABLE STATUS"
    html_section_start "⚠️  MYISAM TABLE STATUS" "⚠️"
    
    echo -e "${YELLOW}Found ${MYISAM_COUNT} MyISAM tables (prone to table-level locking)${RESET}"
    echo "<p style=\"color: #ffc107;\">Found ${MYISAM_COUNT} MyISAM tables (prone to table-level locking)</p>" >> "$HTML_FILE"
    
    MYISAM_TABLES=$(eval "$MYSQL_CMD -e \"
    SELECT 
        CONCAT(table_schema, '.', table_name) as TABLE_NAME,
        ROUND((data_length + index_length) / 1024 / 1024, 2) as SIZE_MB
    FROM information_schema.TABLES 
    WHERE ENGINE = 'MyISAM'
      AND table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
    ORDER BY (data_length + index_length) DESC
    LIMIT 10;\" 2>/dev/null")
    
    echo "$MYISAM_TABLES" | column -t -s $'\t'
    echo "<pre>$(escape_html "$MYISAM_TABLES")</pre>" >> "$HTML_FILE"
    
    html_section_end
fi

# ======================================================================
# 9. LOCKING & TRANSACTION ANALYSIS
# ======================================================================
print_header "🔒 LOCKING & TRANSACTION ANALYSIS"
html_section_start "🔒 LOCKING & TRANSACTION ANALYSIS" "🔒"

LOCK_WAITS=$(echo "$INNODB_STATUS" | grep -c "LOCK WAIT" 2>/dev/null || echo "0")
echo -e "${BOLD}Current InnoDB Lock Waits:${RESET} ${RED}${LOCK_WAITS}${RESET}"
html_info_card "Current Lock Waits" "${LOCK_WAITS}" "$([ "$LOCK_WAITS" -gt 0 ] && echo "highlight" || echo "success")"

TRANSACTIONS=$(eval "$MYSQL_CMD -e \"
SELECT 
    trx_id,
    trx_state,
    trx_started,
    trx_mysql_thread_id as THREAD_ID,
    trx_rows_locked,
    trx_rows_modified
FROM information_schema.INNODB_TRX
ORDER BY trx_started
LIMIT 20\\G\" 2>/dev/null" | grep -v "^\*\*\*" | head -40)

if [ -n "$TRANSACTIONS" ]; then
    echo -e "\n${BOLD}${YELLOW}Active Transactions:${RESET}"
    echo "$TRANSACTIONS"
    html_subsection "Active Transactions"
    echo "<pre>$(escape_html "$TRANSACTIONS")</pre>" >> "$HTML_FILE"
fi

html_section_end

# ======================================================================
# 10. RESOURCE USAGE BY cPanel ACCOUNT
# ======================================================================
print_header "👤 RESOURCE USAGE BY cPanel ACCOUNT"
html_section_start "👤 RESOURCE USAGE BY cPanel ACCOUNT" "👤"

CPANEL_DB_USAGE=$(eval "$MYSQL_CMD -e \"
SELECT 
    SUBSTRING_INDEX(table_schema, '_', 1) as CPANEL_USER,
    COUNT(DISTINCT table_schema) as 'DATABASES',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as TOTAL_MB
FROM information_schema.TABLES 
WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
GROUP BY CPANEL_USER
ORDER BY TOTAL_MB DESC
LIMIT 20;\" 2>/dev/null")

echo -e "${BOLD}Database Usage by cPanel Account:${RESET}"
echo "$CPANEL_DB_USAGE" | column -t -s $'\t'
html_subsection "Database Usage by cPanel Account"
echo "<pre>$(escape_html "$CPANEL_DB_USAGE")</pre>" >> "$HTML_FILE"

CPANEL_CONNECTIONS=$(eval "$MYSQL_CMD -e \"
SELECT 
    SUBSTRING_INDEX(USER, '_', 1) as CPANEL_USER,
    COUNT(*) as CONNECTIONS,
    SUM(CASE WHEN COMMAND != 'Sleep' THEN 1 ELSE 0 END) as ACTIVE_QUERIES
FROM information_schema.PROCESSLIST 
WHERE USER NOT IN ('root', 'system user', 'mysql', 'cpanel', 'leechprotect', 'cphulkd', 'eximstats', 'roundcube', 'horde', 'event_scheduler')
GROUP BY CPANEL_USER
ORDER BY CONNECTIONS DESC
LIMIT 15;\" 2>/dev/null")

echo -e "\n${BOLD}Current Connections by cPanel User:${RESET}"
echo "$CPANEL_CONNECTIONS" | column -t -s $'\t'
html_subsection "Current Connections by cPanel User"
echo "<pre>$(escape_html "$CPANEL_CONNECTIONS")</pre>" >> "$HTML_FILE"

html_section_end

# ======================================================================
# 11. KEY CONFIGURATION VARIABLES
# ======================================================================
print_header "⚙️  KEY CONFIGURATION VARIABLES"
html_section_start "⚙️  KEY CONFIGURATION VARIABLES" "⚙️"

INNODB_BP_SIZE=$(get_variable "innodb_buffer_pool_size")
INNODB_LOG_SIZE=$(get_variable "innodb_log_file_size")
INNODB_FLUSH=$(get_variable "innodb_flush_log_at_trx_commit")
INNODB_IO_CAP=$(get_variable "innodb_io_capacity")
QUERY_CACHE_SIZE=$(get_variable "query_cache_size")
THREAD_CACHE=$(get_variable "thread_cache_size")
TABLE_CACHE=$(get_variable "table_open_cache")
WAIT_TIMEOUT=$(get_variable "wait_timeout")
MAX_ALLOWED_PACKET=$(get_variable "max_allowed_packet")

html_info_grid_start
[ -n "$INNODB_BP_SIZE" ] && html_info_card "innodb_buffer_pool_size" "$(echo "scale=2; $INNODB_BP_SIZE / 1024 / 1024 / 1024" | bc 2>/dev/null) GB"
[ -n "$INNODB_LOG_SIZE" ] && html_info_card "innodb_log_file_size" "$(echo "scale=0; $INNODB_LOG_SIZE / 1024 / 1024" | bc 2>/dev/null) MB"
[ -n "$INNODB_FLUSH" ] && html_info_card "innodb_flush_log_at_trx_commit" "${INNODB_FLUSH}"
[ -n "$INNODB_IO_CAP" ] && html_info_card "innodb_io_capacity" "${INNODB_IO_CAP}"
[ -n "$THREAD_CACHE" ] && html_info_card "thread_cache_size" "${THREAD_CACHE}"
[ -n "$TABLE_CACHE" ] && html_info_card "table_open_cache" "${TABLE_CACHE}"
[ -n "$MAX_CONN" ] && html_info_card "max_connections" "${MAX_CONN}"
[ -n "$WAIT_TIMEOUT" ] && html_info_card "wait_timeout" "${WAIT_TIMEOUT} sec"
html_info_grid_end

echo -e "${BOLD}${CYAN}InnoDB Settings:${RESET}"
[ -n "$INNODB_BP_SIZE" ] && echo -e "  innodb_buffer_pool_size: $(echo "scale=2; $INNODB_BP_SIZE / 1024 / 1024 / 1024" | bc 2>/dev/null) GB"
[ -n "$INNODB_LOG_SIZE" ] && echo -e "  innodb_log_file_size: $(echo "scale=0; $INNODB_LOG_SIZE / 1024 / 1024" | bc 2>/dev/null) MB"

html_section_end

# ======================================================================
# 12. QUICK RECOMMENDATIONS
# ======================================================================
print_header "💡 QUICK RECOMMENDATIONS"
html_section_start "💡 QUICK RECOMMENDATIONS" "💡"

echo -e "${BOLD}${GREEN}Analysis Summary & Recommendations:${RESET}\n"
echo "                <div class=\"recommendation\">" >> "$HTML_FILE"

# Recommendations
if [ -n "$SLOW_QUERIES" ] && [ "$SLOW_QUERIES" -gt 100 ]; then
    echo -e "${RED}⚠️  High number of slow queries (${SLOW_QUERIES})${RESET}"
    echo -e "   ${CYAN}→ Enable slow query log and analyze with pt-query-digest${RESET}"
    cat >> "$HTML_FILE" << HTMLEOF
                    <div class="recommendation-item">
                        <span class="icon">⚠️</span>
                        <span class="text">High number of slow queries (${SLOW_QUERIES})</span>
                        <div class="solution">→ Enable slow query log and analyze with pt-query-digest</div>
                    </div>
HTMLEOF
fi

if [ "$MYISAM_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found ${MYISAM_COUNT} MyISAM tables${RESET}"
    echo -e "   ${CYAN}→ Convert to InnoDB: ALTER TABLE table_name ENGINE=InnoDB;${RESET}"
    cat >> "$HTML_FILE" << HTMLEOF
                    <div class="recommendation-item">
                        <span class="icon">⚠️</span>
                        <span class="text">Found ${MYISAM_COUNT} MyISAM tables</span>
                        <div class="solution">→ Convert to InnoDB: ALTER TABLE table_name ENGINE=InnoDB;</div>
                    </div>
HTMLEOF
fi

if [ -n "$ABORTED_CLIENTS" ] && [ "$ABORTED_CLIENTS" -gt 10000 ]; then
    echo -e "${YELLOW}⚠️  High aborted clients (${ABORTED_CLIENTS})${RESET}"
    echo -e "   ${CYAN}→ Check wait_timeout (currently ${WAIT_TIMEOUT}s)${RESET}"
    cat >> "$HTML_FILE" << HTMLEOF
                    <div class="recommendation-item">
                        <span class="icon">⚠️</span>
                        <span class="text">High aborted clients (${ABORTED_CLIENTS})</span>
                        <div class="solution">→ Check wait_timeout (currently ${WAIT_TIMEOUT}s)</div>
                    </div>
HTMLEOF
fi

if [ -n "$IB_POOL_WAIT_FREE" ] && [ "$IB_POOL_WAIT_FREE" -gt 0 ]; then
    echo -e "${RED}⚠️  Buffer pool wait free detected${RESET}"
    echo -e "   ${CYAN}→ Increase innodb_buffer_pool_size${RESET}"
    cat >> "$HTML_FILE" << HTMLEOF
                    <div class="recommendation-item">
                        <span class="icon">⚠️</span>
                        <span class="text">Buffer pool wait free detected</span>
                        <div class="solution">→ Increase innodb_buffer_pool_size</div>
                    </div>
HTMLEOF
fi

PK_MISSING=$(eval "$MYSQL_CMD -e \"
SELECT COUNT(*) FROM information_schema.TABLES t
LEFT JOIN information_schema.STATISTICS s 
    ON t.table_schema = s.table_schema 
    AND t.table_name = s.table_name 
    AND s.index_name = 'PRIMARY'
WHERE t.table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
  AND t.table_type = 'BASE TABLE'
  AND s.index_name IS NULL;\" -s -N 2>/dev/null")

if [ -n "$PK_MISSING" ] && [ "$PK_MISSING" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found ${PK_MISSING} tables without PRIMARY KEY${RESET}"
    echo -e "   ${CYAN}→ Add auto_increment primary key for better performance${RESET}"
    cat >> "$HTML_FILE" << HTMLEOF
                    <div class="recommendation-item">
                        <span class="icon">⚠️</span>
                        <span class="text">Found ${PK_MISSING} tables without PRIMARY KEY</span>
                        <div class="solution">→ Add auto_increment primary key for better performance</div>
                    </div>
HTMLEOF
fi

if [ -n "$SELECT_FULL_JOIN" ] && [ "$SELECT_FULL_JOIN" -gt 10000 ]; then
    echo -e "${YELLOW}⚠️  High number of full joins (${SELECT_FULL_JOIN})${RESET}"
    echo -e "   ${CYAN}→ Check and optimize indexes on frequently joined tables${RESET}"
    cat >> "$HTML_FILE" << HTMLEOF
                    <div class="recommendation-item">
                        <span class="icon">⚠️</span>
                        <span class="text">High number of full joins (${SELECT_FULL_JOIN})</span>
                        <div class="solution">→ Check and optimize indexes on frequently joined tables</div>
                    </div>
HTMLEOF
fi

echo "                </div>" >> "$HTML_FILE"

html_section_end

# ======================================================================
# Finalize HTML
# ======================================================================
html_end

# Create .htaccess protection
create_htaccess

# Set permissions
chmod 644 "$HTML_FILE" 2>/dev/null

# Get server IP for URL display
SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "\n${GREEN}${BOLD}✓ Analysis Complete!${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${GREEN}📄 HTML Report Generated Successfully!${RESET}\n"
echo -e "${BOLD}📁 File Location:${RESET} ${YELLOW}${HTML_FILE}${RESET}"
echo -e "${BOLD}🌐 Access URL:${RESET} ${CYAN}http://${SERVER_IP}/mysql_analyzer.html${RESET}"
echo -e "${BOLD}🔐 Authentication:${RESET}"
echo -e "   ${BOLD}Username:${RESET} ${GREEN}${AUTH_USER}${RESET}"
echo -e "   ${BOLD}Password:${RESET} ${GREEN}${AUTH_PASS}${RESET}"
[ -f "$BACKUP_FILE" ] && echo -e "\n${BOLD}💾 Previous report backed up to:${RESET} ${BACKUP_FILE}"
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ======================================================================
# END OF SCRIPT
# ======================================================================
echo -e "\n"
