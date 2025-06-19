#!/bin/bash

# HAProxy external-check script for Tor proxies
# Usage: check_tor.sh $1 $2 $3 $4
# $1, $2: NOT_USED (as configured in HAProxy)
# $3: IP address (127.0.0.1)
# $4: Port number

TEST_URL="${TEST_URL:-https://icanhazip.com}"
TIMEOUT="${PROXY_TIMEOUT:-5}"

# Extract parameters
IP="$3"
PORT="$4"

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$$] $1"
}

# Function to test proxy connectivity
test_proxy() {
    local ip="$1"
    local port="$2"

    # Test proxy with curl using HTTPS
    if curl --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
           --proxy "$ip:$port" \
           --silent --output /dev/null \
           "$TEST_URL" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check if Tor process is running
is_tor_process_running() {
    local port="$1"
    local tor_id=$((port - 20000))
    local pid_file="/var/run/tor/$((10000 + tor_id)).pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0  # Process is running
        fi
    fi
    return 1  # Process is not running
}


# Main logic
log_message "Checking Tor proxy $IP:$PORT"

# Test proxy functionality
if test_proxy "$IP" "$PORT"; then
    log_message "Tor proxy $IP:$PORT is working"
    exit 0
else
    log_message "Tor proxy $IP:$PORT is not responding"

    # Check if process is running for diagnostics
    if ! is_tor_process_running "$PORT"; then
        log_message "Tor process for port $PORT is not running - Supervisor should restart it"
    else
        log_message "Tor process is running but proxy not responding - may need circuit refresh"
    fi

    exit 1
fi
