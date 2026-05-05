#!/bin/bash
# Scan for compromised cPanel/WHM session files.
#
# Each check function inspects a single session file and, if the IOC
# matches, calls report_finding with a severity. report_finding records
# the finding, prints a one-line header, and dumps the session for triage.
# A summary of all findings (grouped by severity) is printed at the end.


# Default paths
SESSIONS_DIR="/var/cpanel/sessions"
ACCESS_LOG="/usr/local/cpanel/logs/access_log"

# Flags
VERBOSE=0
PURGE=0
ASSUME_YES=0

# Parse flags
while [ $# -gt 0 ]; do
    case "$1" in
        --verbose)
            VERBOSE=1
            ;;
        --purge)
            PURGE=1
            ;;
        --yes|-y)
            ASSUME_YES=1
            ;;
        --sessions-dir)
            SESSIONS_DIR="$2"; shift
            ;;
        --access-log)
            ACCESS_LOG="$2"; shift
            ;;
        --help|-h)
            echo "Usage: $0 [--verbose] [--purge [--yes]] [--sessions-dir DIR] [--access-log FILE]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# Findings accumulator. Each entry: "SEVERITY|session_file|short_message"
FINDINGS=()
# Ordered list of unique session files that produced findings.
FINDING_SESSIONS=()
# Parallel array: token value associated with each entry in FINDING_SESSIONS
# (first non-empty token seen for that session).
FINDING_TOKENS=()
# Parallel array: highest severity reported for each session (by index)
FINDING_SEVERITIES=()
COUNT_CRITICAL=0
COUNT_WARNING=0
COUNT_INFO=0
COUNT_ATTEMPT=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Extract the value of a key=value line from a session file (first match).
# Use: get_field <file> <key>
get_field() {
    local file="$1" key="$2"
    grep "^${key}=" "$file" | head -1 | cut -d= -f2-
}

hr() {
    echo "    ----------------------------------------------------------------"
}

# Dump full contents of a session file plus related context (matching
# pre-auth file, access_log hits for the injected token, file metadata).
# Use: dump_session <session_file> [token_value]
dump_session() {
    local session_file="$1"
    local token_val="$2"
    local session_name preauth_file
    session_name=$(basename "$session_file")
    preauth_file="$SESSIONS_DIR/preauth/$session_name"

    hr
    echo "    SESSION DUMP: $session_file"
    hr
    echo "    File metadata:"
    ls -la "$session_file" 2>/dev/null | sed 's/^/      /'
    echo
    echo "    Full session contents:"
    sed 's/^/      /' "$session_file"
    echo

    if [ -f "$preauth_file" ]; then
        echo "    Matching pre-auth file: $preauth_file"
        ls -la "$preauth_file" 2>/dev/null | sed 's/^/      /'
        echo "    Pre-auth contents:"
        sed 's/^/      /' "$preauth_file"
        echo
    fi

    if [ -n "$token_val" ] && [ -r "$ACCESS_LOG" ]; then
        echo "    Access log hits for token '$token_val':"
        grep -aF -- "$token_val" "$ACCESS_LOG" | sed 's/^/      /' || echo "      (none)"
        echo
    fi
    hr
}

# Record a finding and print a brief header line. The full session dump is
# deferred to print_summary so that multiple findings for the same session
# are grouped together and the session is only dumped once. When the same
# session matches multiple IOCs at different severities, only the highest
# (CRITICAL > WARNING > ATTEMPT > INFO) is kept.
# Use: report_finding <SEVERITY> <session_file> <token_value> <message>
# SEVERITY is one of: CRITICAL, WARNING, ATTEMPT, INFO
report_finding() {
    local severity="$1"
    local session_file="$2"
    local token_val="$3"
    local message="$4"

    # Severity ranking: CRITICAL=3, WARNING=2, ATTEMPT=1, INFO=0
    local sev_rank=0
    case "$severity" in
        CRITICAL) sev_rank=3 ;;
        WARNING)  sev_rank=2 ;;
        ATTEMPT)  sev_rank=1 ;;
        INFO)     sev_rank=0 ;;
    esac

    local i found=0 prev_sev prev_rank
    for i in "${!FINDING_SESSIONS[@]}"; do
        if [ "${FINDING_SESSIONS[$i]}" = "$session_file" ]; then
            found=1
            prev_sev="${FINDING_SEVERITIES[$i]}"
            case "$prev_sev" in
                CRITICAL) prev_rank=3 ;;
                WARNING)  prev_rank=2 ;;
                ATTEMPT)  prev_rank=1 ;;
                INFO)     prev_rank=0 ;;
            esac
            if [ "$sev_rank" -le "$prev_rank" ]; then
                # Existing finding is at least as severe; ignore.
                return
            fi
            # Upgrade in place: replace severity, token, FINDINGS entry,
            # and roll back the previous severity counter so the new one
            # can be incremented below without double-counting.
            FINDING_SEVERITIES[$i]="$severity"
            [ -n "$token_val" ] && FINDING_TOKENS[$i]="$token_val"
            local j
            for j in "${!FINDINGS[@]}"; do
                local entry="${FINDINGS[$j]}"
                local entry_sev="${entry%%|*}"
                local entry_file="${entry#*|}"; entry_file="${entry_file%%|*}"
                if [ "$entry_file" = "$session_file" ] && [ "$entry_sev" = "$prev_sev" ]; then
                    FINDINGS[$j]="${severity}|${session_file}|${message}"
                    break
                fi
            done
            case "$prev_sev" in
                CRITICAL) COUNT_CRITICAL=$((COUNT_CRITICAL - 1)) ;;
                WARNING)  COUNT_WARNING=$((COUNT_WARNING - 1))   ;;
                ATTEMPT)  COUNT_ATTEMPT=$((COUNT_ATTEMPT - 1))   ;;
                INFO)     COUNT_INFO=$((COUNT_INFO - 1))         ;;
            esac
            break
        fi
    done

    if [ "$found" -eq 0 ]; then
        FINDING_SESSIONS+=("$session_file")
        FINDING_TOKENS+=("$token_val")
        FINDING_SEVERITIES+=("$severity")
        FINDINGS+=("${severity}|${session_file}|${message}")
    fi

    case "$severity" in
        CRITICAL) COUNT_CRITICAL=$((COUNT_CRITICAL + 1)) ;;
        WARNING)  COUNT_WARNING=$((COUNT_WARNING + 1))   ;;
        ATTEMPT)  COUNT_ATTEMPT=$((COUNT_ATTEMPT + 1))   ;;
        INFO)     COUNT_INFO=$((COUNT_INFO + 1))         ;;
    esac

    echo "[${severity}] ${message}: ${session_file}"
}

# ---------------------------------------------------------------------------
# IOC checks
# ---------------------------------------------------------------------------

# IOC 0: token_denied counter alongside cp_security_token, in a session
# whose origin is badpass or otherwise non-benign.
#
# - token_denied is incremented by do_token_denied() (cpsrvd.pl:3821)
#   every time a request supplies the wrong cp_security_token. The
#   session is killed on the third failure.
# - cp_security_token itself is set by newsession() unconditionally
#   while security tokens are enabled (Cpanel/Server.pm:2290), so its
#   presence is NOT by itself an IOC. The pair (token_denied,
#   cp_security_token) tells us only that someone is actively trying
#   tokens against this session.
#
# Auth markers (successful_*_auth_with_timestamp, hasroot=1,
# tfa_verified=1, or an access_log hit on the security token) cannot
# legitimately appear in a badpass session: the badpass call site
# (Cpanel/Server.pm:1244-1252) doesn't pass them, hasroot is not even
# in _SESSION_PARTS (Cpanel/Server.pm:2216-2247), and tfa_verified is
# forced to 0 unless the caller passes a truthy value (line 2295).
#
# Severity tiers:
#   CRITICAL - badpass origin AND auth markers present (post-exploit)
#   INFO     - badpass origin, no auth markers, pass looks like a real
#              encoded password (likely an unrelated failed login that
#              happened to receive bad-token traffic)
#   WARNING  - origin is neither badpass nor a known-benign method
#              (handle_form_login, create_user_session,
#              handle_auth_transfer); the suspicious origin itself is
#              the IOC
#
# Legitimate badpass sessions never carry a pass= line (the badpass
# call site at Cpanel/Server.pm:1244-1252 does not pass `pass` to
# newsession, and saveSession only writes pass= when length is
# non-zero - Cpanel/Session.pm:181). When we see one anyway we defer
# classification to IOC 5 (check_failed_exploit_attempt), which flags
# it as ATTEMPT.
check_token_denied_with_injected_token() {
    local session_file="$1"

    grep -q '^token_denied='      "$session_file" || return
    grep -q '^cp_security_token=' "$session_file" || return

    local token_val external_auth internal_auth hasroot tfa used
    token_val=$(get_field      "$session_file" cp_security_token)
    external_auth=$(get_field  "$session_file" successful_external_auth_with_timestamp)
    internal_auth=$(get_field  "$session_file" successful_internal_auth_with_timestamp)
    hasroot=$(get_field        "$session_file" hasroot)
    tfa=$(get_field            "$session_file" tfa_verified)
    used=""
    if [ -r "$ACCESS_LOG" ]; then
        used=$(grep -aF -- "$token_val" "$ACCESS_LOG" | grep -m1 " 200 ")
    fi

    local has_auth_markers=0
    if [ -n "$external_auth" ] || [ -n "$internal_auth" ] \
       || [ "$hasroot" = "1" ] || [ "$tfa" = "1" ] || [ -n "$used" ]; then
        has_auth_markers=1
    fi

    if grep -q '^origin_as_string=.*method=badpass' "$session_file"; then
        if [ "$has_auth_markers" -eq 1 ]; then
            report_finding CRITICAL "$session_file" "$token_val" \
                "Exploitation artifact - token_denied with injected cp_security_token (badpass origin, token used)"
        else
            # A pass= line on a badpass session is itself anomalous;
            # defer to IOC 5 (ATTEMPT).
            if grep -q '^pass=' "$session_file"; then
                return
            fi
            report_finding INFO "$session_file" "$token_val" \
                "Possible injected session (badpass origin, no usage observed)"
        fi
    elif grep -q '^origin_as_string=.*method=handle_form_login' "$session_file" || \
         grep -q '^origin_as_string=.*method=create_user_session' "$session_file" || \
         grep -q '^origin_as_string=.*method=handle_auth_transfer' "$session_file"; then
        # Known-benign origins where token_denied + cp_security_token
        # genuinely happens during normal use.
        return
    else
        report_finding WARNING "$session_file" "$token_val" \
            "Suspicious session with token_denied + cp_security_token (non-badpass origin)"
    fi
}

# IOC 1: A session that still has its pre-auth marker file but already
# contains an auth-success timestamp (external or internal).
#
# write_session creates $SESSIONS_DIR/preauth/<session_name> when the
# session is written with needs_auth=1, and removes that marker once
# needs_auth is cleared on promotion (Cpanel/Session.pm:225-235). A
# legitimately authenticated session therefore never has both the
# preauth marker and an auth-success timestamp at the same time.
#
# Both successful_external_auth_with_timestamp and
# successful_internal_auth_with_timestamp are checked: the original
# poc.py payload injects the external variant; the watchtowr payload
# (poc/poc_watchtowr.py:35) injects the internal variant.
check_preauth_with_auth_attrs() {
    local session_file="$1"
    local session_name preauth_file
    session_name=$(basename "$session_file")
    preauth_file="$SESSIONS_DIR/preauth/$session_name"

    [ -f "$preauth_file" ] || return

    local marker
    if grep -qE '^successful_external_auth_with_timestamp=' "$session_file"; then
        marker="successful_external_auth_with_timestamp"
    elif grep -qE '^successful_internal_auth_with_timestamp=' "$session_file"; then
        marker="successful_internal_auth_with_timestamp"
    else
        return
    fi

    report_finding CRITICAL "$session_file" \
        "$(get_field "$session_file" cp_security_token)" \
        "Injected session - ${marker} present in pre-auth session"
}

# IOC 2: tfa_verified=1 outside of a legitimate origin method.
#
# tfa_verified=1 is set in only two places:
#   - Cpanel/Security/Authn/TwoFactorAuth/Verify.pm:122, after a real
#     TFA token validation succeeds.
#   - Cpanel/Server.pm:2295, when a caller passes tfa_verified=1 to
#     newsession().
# In both cases the legitimate origin method is one of handle_form_login,
# create_user_session, or handle_auth_transfer. tfa_verified=1 with any
# other origin (notably badpass) cannot occur in a benign flow.
check_tfa_with_bad_origin() {
    local session_file="$1"

    grep -qE '^tfa_verified=1$' "$session_file" || return
    grep -q '^origin_as_string=.*method=handle_form_login'    "$session_file" && return
    grep -q '^origin_as_string=.*method=create_user_session'  "$session_file" && return
    grep -q '^origin_as_string=.*method=handle_auth_transfer' "$session_file" && return

    report_finding WARNING "$session_file" \
        "$(get_field "$session_file" cp_security_token)" \
        "Session with tfa_verified=1 but suspicious origin"
}

# IOC 3: Session file contains a line that is not in `key=value` form.
#
# Three structural invariants together guarantee that every legitimate
# line matches ^[A-Za-z_][A-Za-z0-9_]*=:
#
#   1. write_session serializes via Cpanel::Config::FlushConfig::flushConfig
#      with '=' as the separator (Cpanel/Session.pm:221), so the on-disk
#      format is one key=value pair per line.
#   2. Keys come from a fixed whitelist (_SESSION_PARTS at
#      Cpanel/Server.pm:2216-2247, applied at lines 2268-2270), so they
#      always match the identifier shape above.
#   3. Cpanel::Session::filter_sessiondata strips \r\n from every value
#      (Cpanel/Session.pm:315) and additionally strips \r\n=, from origin
#      sub-values (line 312), so values can never re-introduce line
#      breaks. The `pass` value is additionally encoded by saveSession
#      (Cpanel/Session.pm:181-189) into either lowercase hex (with-secret
#      via Cpanel::Session::Encoder->encode_data) or the literal prefix
#      `no-ob:` followed by lowercase hex (no-secret via
#      Cpanel::Session::Encoder->hex_encode_only), so it cannot
#      reintroduce structural characters either.
#
# Any non-blank line that fails the regex is the footprint of an
# injection that bypassed these invariants - typically raw payload bytes
# that didn't form valid key=value pairs. Note: an injection whose
# smuggled lines DO match key=value (e.g. the watchtowr payload at
# poc/poc_watchtowr.py:35, which fabricates successful_internal_auth_
# with_timestamp/user/tfa_verified/hasroot lines) will not trip this
# check; it is caught by IOC-0 and IOC-4 instead.
check_malformed_session_line() {
    local session_file="$1"

    # Look for any non-blank line that doesn't start with key=...
    grep -nE -v '^[A-Za-z_][A-Za-z0-9_]*=|^[[:space:]]*$' "$session_file" >/dev/null 2>&1 || return

    report_finding CRITICAL "$session_file" \
        "$(get_field "$session_file" cp_security_token)" \
        "Malformed session line(s) detected (not key=value - newline injection footprint)"
}

# IOC 4: badpass origin combined with markers that no legitimate cpsrvd
# code path writes into a badpass session.
#
# The badpass call site (Cpanel/Server.pm:1244-1252) is:
#
#   $randsession = $self->newsession(
#       'needs_auth' => 1,
#       %security_token_options,            # adds cp_security_token
#       'origin' => { 'method' => 'badpass' },
#   );
#
# %security_token_options is why badpass sessions legitimately carry
# cp_security_token, but no auth-related options are ever supplied.
# newsession() filters %OPTS through the _SESSION_PARTS whitelist
# (Cpanel/Server.pm:2216-2247, applied at lines 2268-2270), so any key
# not in that whitelist cannot land in the session via newsession at
# all. Per marker:
#
#   successful_external_auth_with_timestamp - whitelisted, but the
#       badpass caller doesn't pass it
#   successful_internal_auth_with_timestamp - same
#   tfa_verified=1 - newsession unconditionally writes 0 unless the
#       caller passed a truthy value (Cpanel/Server.pm:2295), and the
#       badpass caller doesn't
#   hasroot=1 - NOT in _SESSION_PARTS, so newsession cannot write it
#       for ANY session. A repo-wide grep finds no caller of
#       Cpanel::Session::Modify->set('hasroot', ...) either: hasroot is
#       never written to a session by legitimate code. Its presence in
#       any session file is conclusive evidence of newline injection
#       (the watchtowr payload at poc/poc_watchtowr.py:35 smuggles
#       hasroot=1 via \r\n in a user-controlled field).
check_badpass_with_auth_markers() {
    local session_file="$1"

    grep -q '^origin_as_string=.*method=badpass' "$session_file" || return

    local markers=()
    grep -q '^successful_external_auth_with_timestamp=' "$session_file" \
        && markers+=("successful_external_auth_with_timestamp")
    grep -q '^successful_internal_auth_with_timestamp=' "$session_file" \
        && markers+=("successful_internal_auth_with_timestamp")
    grep -qE '^hasroot=1$'      "$session_file" && markers+=("hasroot=1")
    grep -qE '^tfa_verified=1$' "$session_file" && markers+=("tfa_verified=1")

    [ "${#markers[@]}" -gt 0 ] || return

    local joined
    joined=$(IFS=,; echo "${markers[*]}")
    report_finding CRITICAL "$session_file" \
        "$(get_field "$session_file" cp_security_token)" \
        "badpass origin combined with authenticated markers ($joined) - impossible in benign flow"
}

# IOC 5: Failed exploit attempt - a badpass session that carries a
# pass= line, a token_denied counter, and no auth markers.
#
# A legitimate badpass session is created at Cpanel/Server.pm:1244-1252:
#
#   $randsession = $self->newsession(
#       'needs_auth' => 1,
#       %security_token_options,
#       'origin' => { 'method' => 'badpass' },
#   );
#
# %security_token_options carries only cp_security_token,
# requested_token_at_next_login, and previous_session_user
# (Cpanel/Server.pm:1205-1226) - never `pass`. saveSession only
# writes a pass= line when length($session_ref->{pass}) is non-zero
# (Cpanel/Session.pm:181), so legitimate badpass sessions have no
# pass= line at all.
#
# An exploit that tampers with a user-controlled field on a
# badpass-bound request leaves a pass= line behind (saveSession
# encodes it as `<hex>` or `no-ob:<hex>` per Cpanel/Session.pm:181-189,
# but the format is irrelevant - its presence is the indicator). Combined
# with token_denied (someone was poking at cp_security_token) and the
# absence of auth markers (the injection didn't promote - otherwise
# IOC-0 or IOC-4 fires CRITICAL), this is the signature of a failed
# exploit attempt.
check_failed_exploit_attempt() {
    local session_file="$1"

    grep -q '^origin_as_string=.*method=badpass' "$session_file" || return
    grep -q '^token_denied=' "$session_file" || return

    # If auth markers are present, IOC-4 (CRITICAL) handles it.
    grep -q '^successful_internal_auth_with_timestamp=' "$session_file" && return
    grep -q '^successful_external_auth_with_timestamp=' "$session_file" && return

    # Legitimate badpass sessions never carry pass=.
    grep -q '^pass=' "$session_file" || return

    report_finding ATTEMPT "$session_file" "$(get_field "$session_file" cp_security_token)" \
        "Failed exploit attempt (badpass origin, token_denied, no auth markers, anomalous pass= line)"
}

# Inspect a *.lock file (Cpanel::SafeFile dotlock) and confirm it looks
# like a real lock before silently skipping it.
#
# Cpanel::Session uses Cpanel::SafeFile to write the session file to
# disk (serialization itself is handled in the session code). SafeFile
# creates a sibling dotlock at <session>.lock for the duration of every
# write and, on crash/abort, may leave it behind permanently. The lock contents
# are written by Cpanel::SafeFileLock::write_lock_contents as "$$\n$0\n"
# - first line is the PID, second line is the program name. These are
# not key=value pairs, so without a guard they trip
# check_malformed_session_line as a CRITICAL false positive.
#
# The CVE-2026-41940 exploit vector is the session file content, not the
# lock file, so a lock file that doesn't look right is not by itself an
# exploitation indicator. Emit a stderr notice for operator awareness and
# leave the SCAN SUMMARY counters alone.
check_lock_file() {
    local lock_file="$1"
    local first_line
    first_line=$(grep -m1 -v '^[[:space:]]*$' "$lock_file" 2>/dev/null)
    if [[ "$first_line" =~ ^[0-9]+$ ]]; then
        return
    fi
    echo "[NOTICE] Skipping unexpected .lock contents: $lock_file" >&2
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

scan_sessions() {
    local session_file
    while IFS= read -r -d '' session_file; do
        # SafeFile dotlocks come in two forms: <session>.lock (the
        # final lock) and <session>.lock-<hex-and-hyphens> (the temp
        # name SafeFile writes before atomic-renaming into place; it
        # can also be left behind on crash). Skip both.
        #
        # Vim creates a .swp swap file alongside any file it opens,
        # so an operator inspecting a session in vim leaves one
        # behind. The format is binary and not a session.
        case "$session_file" in
            *.lock | *.lock-*)
                check_lock_file "$session_file"
                continue
                ;;
            *.swp)
                continue
                ;;
        esac
        check_token_denied_with_injected_token "$session_file"
        check_preauth_with_auth_attrs          "$session_file"
        check_tfa_with_bad_origin              "$session_file"
        check_malformed_session_line           "$session_file"
        check_badpass_with_auth_markers        "$session_file"
        check_failed_exploit_attempt           "$session_file"
    done < <(find "$SESSIONS_DIR/raw" -type f -print0 2>/dev/null)
}


print_summary() {
    local total=$((COUNT_CRITICAL + COUNT_WARNING + COUNT_INFO + COUNT_ATTEMPT))

    echo
    echo "================================================================="
    echo "                       SCAN SUMMARY"
    echo "================================================================="
    echo "  CRITICAL findings: $COUNT_CRITICAL"
    echo "  WARNING  findings: $COUNT_WARNING"
    echo "  ATTEMPT  findings: $COUNT_ATTEMPT"
    echo "  INFO     findings: $COUNT_INFO"
    echo "  Total            : $total"
    echo "-----------------------------------------------------------------"

    if [ "$total" -eq 0 ]; then
        echo "[+] No indicators of compromise found."
        return
    fi

    # --purge has destructive blast radius (live session files for every
    # logged-in user). Require either --yes for non-interactive use, or
    # an explicit "yes" at an attached TTY.
    if [ "$PURGE" -eq 1 ] && [ "$ASSUME_YES" -ne 1 ]; then
        if [ ! -t 0 ]; then
            echo "[ERROR] --purge requires --yes when stdin is not a TTY (cron, pipes, etc)" >&2
            echo "        Re-run with --yes to confirm deletion." >&2
            exit 64
        fi
        echo
        echo "About to delete ${#FINDING_SESSIONS[@]} session file(s) plus matching preauth markers."
        local confirm=""
        read -r -p "Type 'yes' to confirm: " confirm
        if [ "$confirm" != "yes" ]; then
            echo "[+] Aborted; no files deleted."
            PURGE=0
        fi
    fi


    # For each unique session, print only the highest-severity finding, then dump/purge as needed.
    local i session token severity message found=0
    for i in "${!FINDING_SESSIONS[@]}"; do
        session="${FINDING_SESSIONS[$i]}"
        token="${FINDING_TOKENS[$i]}"
        severity="${FINDING_SEVERITIES[$i]}"
        found=0
        # Find the first matching finding for this session and severity.
        # Use `read` with three names so the last variable (entry_msg)
        # absorbs any remaining `|` characters - the previous `${var##*|}`
        # form took only the suffix after the LAST `|`, which would
        # silently truncate any future message that contained one.
        for entry in "${FINDINGS[@]}"; do
            local entry_sev entry_file entry_msg
            IFS='|' read -r entry_sev entry_file entry_msg <<< "$entry"
            if [ "$entry_file" = "$session" ] && [ "$entry_sev" = "$severity" ]; then
                message="$entry_msg"
                found=1
                break
            fi
        done
        echo
        echo "================================================================="
        echo "  SESSION: $session"
        echo "================================================================="
        echo "  Findings:"
        if [ "$found" -eq 1 ]; then
            printf "    [%-8s] %s\n" "$severity" "$message"
        else
            printf "    [%-8s] %s\n" "$severity" "(no message found)"
        fi
        echo
        if [ "$VERBOSE" -eq 1 ]; then
            dump_session "$session" "$token"
        fi
        if [ "$PURGE" -eq 1 ]; then
            echo "    [ACTION] Deleting session file: $session"
            rm -f -- "$session"
            local preauth_marker="$SESSIONS_DIR/preauth/$(basename "$session")"
            if [ -e "$preauth_marker" ]; then
                echo "    [ACTION] Deleting preauth marker: $preauth_marker"
                rm -f -- "$preauth_marker"
            fi
        fi
    done

    if [ "$COUNT_CRITICAL" -gt 0 ] || [ "$COUNT_WARNING" -gt 0 ]; then
        echo
        echo "[!] INDICATORS OF COMPROMISE DETECTED - IMMEDIATE ACTION REQUIRED"
        echo "    1. Purge all affected sessions"
        echo "    2. Force password reset for root and all WHM users"
        echo "    3. Audit /var/log/wtmp and WHM access logs for unauthorized access"
        echo "    4. Check for persistence mechanisms (cron, SSH keys, backdoors)"
    fi
}

if [ ! -d "$SESSIONS_DIR/raw" ]; then
    echo "[ERROR] Sessions directory not found: $SESSIONS_DIR/raw" >&2
    echo "        Pass --sessions-dir DIR to point at a different location" >&2
    echo "        (the default is /var/cpanel/sessions)." >&2
    exit 64
fi

echo "[*] Scanning session files for injection indicators..."
scan_sessions
print_summary

# Exit codes (for cron / monitoring):
#   2 - at least one CRITICAL or WARNING finding (compromise indicators)
#   1 - only ATTEMPT or INFO findings (probing, no confirmed compromise)
#   0 - clean scan
if [ "$COUNT_CRITICAL" -gt 0 ] || [ "$COUNT_WARNING" -gt 0 ]; then
    exit 2
elif [ "$COUNT_ATTEMPT" -gt 0 ] || [ "$COUNT_INFO" -gt 0 ]; then
    exit 1
fi
exit 0
