# rotating-proxy-ng-plus

[![Docker Pulls](https://img.shields.io/docker/pulls/noma4i/rotating-proxy-ng-plus.svg)](https://hub.docker.com/r/noma4i/rotating-proxy-ng-plus/)

A lightweight, fully automated rotating Tor proxy solution with intelligent load balancing and automatic failover.

This is a completely rewritten fork of the original repo https://github.com/hackera10/rotating-proxy-ng-plus, designed to solve issues with old dependencies, memory leaks, and unreliable process management.

## Quick Start

### Using Docker Compose (Recommended)
```bash
# Clone and start
git clone https://github.com/noma4i/rotating-proxy-ng-plus.git
cd rotating-proxy-ng-plus
docker-compose up -d

# Test the proxy
curl --proxy 127.0.0.1:5566 https://api.my-ip.io/v2/ip.json

# View HAProxy statistics
open http://127.0.0.1:4444/haproxy?stats
```

### Using Docker Run
```bash
# Start with default 10 Tor instances
docker run -d -p 5566:5566 -p 4444:4444 noma4i/rotating-proxy-ng-plus

# Start with a custom number of instances
docker run -d -p 5566:5566 -p 4444:4444 --env tors=20 noma4i/rotating-proxy-ng-plus

# Slower circuit rotation (change exit IP every 60s instead of the default 30s)
docker run -d -p 5566:5566 -p 4444:4444 \
  --env tors=6 --env NEW_CIRCUIT_PERIOD=60 --env MAX_CIRCUIT_DIRTINESS=60 \
  noma4i/rotating-proxy-ng-plus
```

### Build from Source
```bash
# Build the container
docker build -t rotating-proxy-ng-plus .

# Run it
docker run -d -p 5566:5566 -p 4444:4444 rotating-proxy-ng-plus
```

## Configuration

All runtime tuning is done through environment variables — there is nothing to
edit inside the image. Pass them with `--env KEY=value` (Docker run) or under
`environment:` (Docker Compose); anything you don't set falls back to the
defaults below.

### Environment Variables
| Variable                | Default | Description |
|-------------------------|---------|-------------|
| `tors`                  | `10`    | Number of independent Tor instances behind HAProxy. More instances = more concurrent exit IPs, but more CPU/RAM (~100 MB per instance). |
| `NEW_CIRCUIT_PERIOD`    | `30`    | Tor `--NewCircuitPeriod` (seconds): how often Tor is asked to build a fresh circuit. Lower = exit IP changes more often, more churn/CPU. |
| `MAX_CIRCUIT_DIRTINESS` | `30`    | Tor `--MaxCircuitDirtiness` (seconds): max age a circuit is reused for new connections before it is rotated. |

Defaults live in `start.sh`. `docker-compose.yml` overrides `tors=5` for local use.

> **Fixed Tor flags** (not env-configurable, set in `start.sh`): `SocksPort 0`
> (HTTP tunnel only), `UseEntryGuards 0`, `CircuitBuildTimeout 5`,
> `MaxMemInQueues "64 MB"` per instance. Edit `start.sh` if you need to change them.

### Example with Custom Settings
```bash
docker run -d \
  -p 5566:5566 \
  -p 4444:4444 \
  --env tors=6 \
  --env NEW_CIRCUIT_PERIOD=45 \
  --env MAX_CIRCUIT_DIRTINESS=45 \
  noma4i/rotating-proxy-ng-plus
```

Docker Compose equivalent:
```yaml
services:
  proxy:
    image: noma4i/rotating-proxy-ng-plus:latest
    ports:
      - "5566:5566"
      - "4444:4444"
    environment:
      tors: "6"
      NEW_CIRCUIT_PERIOD: "45"
      MAX_CIRCUIT_DIRTINESS: "45"
    restart: unless-stopped
```

### HAProxy Web Statistics
Access the HAProxy statistics dashboard at: **http://127.0.0.1:4444/haproxy?stats**

### Testing Proxy Rotation
```bash
# Test multiple requests to see different IPs
for i in {1..5}; do
  curl --proxy 127.0.0.1:5566 -s https://api.my-ip.io/v2/ip.json | jq '.ip'
done
```

## Resource Usage

Measured on Apple Silicon (native `arm64` image), idle — i.e. circuits built but
no proxy traffic flowing. Memory scales roughly linearly at **~100 MB per Tor
instance** and settles within ~2-3 minutes as Tor finishes loading the directory
consensus. CPU at idle stays in the low single-digit percent; it rises with the
volume of traffic and how aggressively you rotate circuits.

| `tors` | Memory (RSS, whole container) | CPU (idle) |
|--------|-------------------------------|------------|
| 3      | ~330 MB                       | <2%        |
| 6      | ~590 MB                       | ~1.6%      |
| 10     | ~970 MB                       | ~1-4%      |

Notes:
- Figures cover the whole container (HAProxy + supervisord + all Tor instances).
- `MaxMemInQueues "64 MB"` per instance caps worst-case queue memory under heavy
  load; steady-state usage is well below that.
- On non-`arm64`/`amd64` hosts the image runs under QEMU emulation, which inflates
  both CPU and memory significantly — use a host matching one of the published
  platforms.
