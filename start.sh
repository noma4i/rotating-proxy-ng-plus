#!/bin/bash

set -e

# Configuration
TOR_INSTANCES=${tors:-10}
HAPROXY_PORT=5566
STATS_PORT=4444

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Create necessary directories
setup_directories() {
    log "Setting up directories"

    # Supervisor directories
    mkdir -p /var/log/supervisor /var/run

    # HAProxy directories
    mkdir -p /var/lib/haproxy /var/run/haproxy /var/log/haproxy

    # Tor directories
    mkdir -p /var/run/tor
    for ((i=0; i<TOR_INSTANCES; i++)); do
        tor_data_dir="/var/lib/tor/$((10000 + i))"
        mkdir -p "$tor_data_dir"
        chmod 700 "$tor_data_dir"
    done
}

# Generate Supervisor config
generate_supervisor_config() {
    log "Generating Supervisor configuration for $TOR_INSTANCES Tor instances"

    cat > /etc/supervisord.conf <<EOF
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[supervisord]
logfile=/var/log/supervisord.log
pidfile=/var/run/supervisord.pid
childlogdir=/var/log/supervisor
nodaemon=false
minfds=1024
minprocs=200

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[program:haproxy]
command=/usr/sbin/haproxy -f /usr/local/etc/haproxy.cfg -db
autostart=true
autorestart=true
startsecs=5
startretries=3
stdout_logfile=/var/log/supervisor/haproxy.log
stderr_logfile=/var/log/supervisor/haproxy.log

EOF

    # Add Tor instances
    for ((i=0; i<TOR_INSTANCES; i++)); do
        http_port=$((20000 + i))
        data_dir="/var/lib/tor/$((10000 + i))"
        pid_file="/var/run/tor/$((10000 + i)).pid"

        cat >> /etc/supervisord.conf <<EOF
[program:tor$i]
command=tor --SocksPort 0 --HTTPTunnelPort $http_port --NewCircuitPeriod 15 --MaxCircuitDirtiness 15 --UseEntryGuards 0 --CircuitBuildTimeout 5 --DataDirectory $data_dir --PidFile $pid_file --Log "warn syslog"
autostart=true
autorestart=true
startsecs=5
startretries=999999
stdout_logfile=/var/log/supervisor/tor$i.log
stderr_logfile=/var/log/supervisor/tor$i.log

EOF
    done
}

# Generate HAProxy config
generate_haproxy_config() {
    log "Generating HAProxy configuration for $TOR_INSTANCES backends"

    cat > /usr/local/etc/haproxy.cfg <<EOF
global
  maxconn 1024
  daemon
  pidfile /var/run/haproxy/haproxy.pid
  external-check
  insecure-fork-wanted

defaults
  maxconn 1024
  option  dontlognull
  retries 3
  timeout connect 5s
  timeout client 60s
  timeout server 60s

listen stats
  bind *:$STATS_PORT
  mode http
  maxconn 10
  timeout client      100s
  timeout server      100s
  timeout connect      100s
  timeout queue   100s
  stats enable
  stats hide-version
  stats refresh 5s
  stats show-node
  stats uri /haproxy?stats

frontend rotating_proxies
  mode tcp
  bind *:$HAPROXY_PORT
  default_backend tor

backend tor
  mode tcp
  balance roundrobin
  option external-check
  external-check path "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  external-check command /usr/local/bin/check_tor.sh

EOF

    # Add backend servers
    for ((i=0; i<TOR_INSTANCES; i++)); do
        http_port=$((20000 + i))
        echo "  server tor$http_port 127.0.0.1:$http_port check inter 10s fastinter 5s downinter 5s rise 2 fall 2" >> /usr/local/etc/haproxy.cfg
    done
}

# Start Supervisor
start_supervisor() {
    log "Starting Supervisor to manage all processes"
    /usr/bin/supervisord -c /etc/supervisord.conf

    log "Waiting for all processes to initialize"
    sleep 30

    # Check status
    supervisorctl status
}

# Monitor processes
monitor() {
    log "Starting monitoring loop"

    while true; do
        sleep 60

        # Check if supervisor is running
        if ! pgrep supervisord > /dev/null; then
            log "ERROR: Supervisor died, exiting"
            exit 1
        fi

        # Optional: Log status
        if [ "$DEBUG" = "1" ]; then
            log "Supervisor status:"
            supervisorctl status 2>/dev/null || log "Failed to get supervisor status"
        fi
    done
}

# Cleanup function
cleanup() {
    log "Shutting down services"

    # Stop all supervised processes
    supervisorctl stop all 2>/dev/null || true

    # Stop supervisor itself
    if [ -f /var/run/supervisord.pid ]; then
        kill $(cat /var/run/supervisord.pid) 2>/dev/null || true
    fi

    exit 0
}

# Handle signals
trap cleanup TERM INT

# Main execution
main() {
    log "Starting rotating Tor proxy with $TOR_INSTANCES instances"

    setup_directories
    generate_supervisor_config
    generate_haproxy_config
    start_supervisor
    monitor
}

# Run main function
main
