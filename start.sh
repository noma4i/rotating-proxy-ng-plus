#!/bin/bash

set -e

# Configuration
TOR_INSTANCES=${tors:-10}
HAPROXY_PORT=5566
STATS_PORT=4444

# Circuit rotation cadence (seconds). Lower = more frequent IP changes, more churn.
NEW_CIRCUIT_PERIOD=${NEW_CIRCUIT_PERIOD:-30}
MAX_CIRCUIT_DIRTINESS=${MAX_CIRCUIT_DIRTINESS:-30}

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Create necessary directories
setup_directories() {
    log "Setting up directories"

    # Supervisor runtime directory (socket + pidfile). Logs go to stdout, not files.
    mkdir -p /var/run

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
logfile=/dev/null
pidfile=/var/run/supervisord.pid
nodaemon=true
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
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

EOF

    # Add Tor instances
    for ((i=0; i<TOR_INSTANCES; i++)); do
        http_port=$((20000 + i))
        data_dir="/var/lib/tor/$((10000 + i))"
        pid_file="/var/run/tor/$((10000 + i)).pid"

        cat >> /etc/supervisord.conf <<EOF
[program:tor$i]
command=tor --SocksPort 0 --HTTPTunnelPort $http_port --NewCircuitPeriod $NEW_CIRCUIT_PERIOD --MaxCircuitDirtiness $MAX_CIRCUIT_DIRTINESS --UseEntryGuards 0 --CircuitBuildTimeout 5 --MaxMemInQueues "64 MB" --DataDirectory $data_dir --PidFile $pid_file --Log "notice stdout"
autostart=true
autorestart=true
startsecs=5
startretries=999999
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

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

defaults
  maxconn 1024
  option  dontlognull
  retries 3
  timeout connect 5s
  timeout client 60s
  timeout server 60s

frontend stats
  bind *:$STATS_PORT
  mode http
  maxconn 10
  timeout client      100s
  timeout server      100s
  timeout connect      100s
  timeout queue   100s
  stats enable
  stats admin if TRUE
  stats refresh 10s
  stats show-node
  stats uri /haproxy?stats

frontend rotating_proxies
  mode tcp
  bind *:$HAPROXY_PORT
  default_backend tor

backend tor
  mode tcp
  balance roundrobin

EOF

    # Add backend servers. Plain TCP health-check (connect to the Tor HTTPTunnel
    # port): a dead instance is pulled from rotation and Supervisor restarts it.
    # (HAProxy 3.4 external-check segfaults on Alpine/musl, so no curl-based check.)
    for ((i=0; i<TOR_INSTANCES; i++)); do
        http_port=$((20000 + i))
        echo "  server tor$http_port 127.0.0.1:$http_port check inter 10s fastinter 5s downinter 5s rise 2 fall 2" >> /usr/local/etc/haproxy.cfg
    done
}

# Main execution
main() {
    log "Starting rotating Tor proxy with $TOR_INSTANCES instances"

    setup_directories
    generate_supervisor_config
    generate_haproxy_config

    # Hand off to supervisord in the foreground as the container's main process.
    # It reaps and restarts children itself and forwards SIGTERM for graceful
    # shutdown; Docker's restart policy is the single authority on container life.
    log "Starting Supervisor (foreground) to manage all processes"
    exec /usr/bin/supervisord -n -c /etc/supervisord.conf
}

# Run main function
main
