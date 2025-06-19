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
```

### Using Docker Run
```bash
# Start with default 10 Tor instances
docker run -d -p 5566:5566 -p 4444:4444 noma4i/rotating-proxy-ng-plus

# Start with custom number of instances
docker run -d -p 5566:5566 -p 4444:4444 --env tors=20 noma4i/rotating-proxy-ng-plus

# With debug logging
docker run -d -p 5566:5566 -p 4444:4444 --env DEBUG=1 noma4i/rotating-proxy-ng-plus
```

### Build from Source
```bash
# Build the container
docker build -t rotating-proxy-ng-plus .

# Run it
docker run -d -p 5566:5566 -p 4444:4444 rotating-proxy-ng-plus
```

## Configuration

### Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `tors` | `10` | Number of Tor instances to run |
| `DEBUG` | `0` | Enable debug logging (1 to enable) |
| `TEST_URL` | `https://icanhazip.com` | URL for proxy health checks |
| `PROXY_TIMEOUT` | `5` | Timeout for proxy tests (seconds) |

### Example with Custom Settings
```bash
docker run -d \
  -p 5566:5566 \
  -p 4444:4444 \
  --env tors=15 \
  --env DEBUG=1 \
  --env PROXY_TIMEOUT=10 \
  noma4i/rotating-proxy-ng-plus
```
