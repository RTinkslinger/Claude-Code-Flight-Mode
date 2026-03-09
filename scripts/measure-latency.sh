#!/bin/bash
# Flight Mode Latency Measurement
# Run periodically during flight to capture network conditions
# Usage: bash measure-latency.sh [--header] >> measurements/YYYY-MM-DD-carrier-route.csv
#
# Run with --header first to create CSV, then without to append data points
# Recommended: every 15-30 min during flight

if [ "$1" = "--header" ]; then
  echo "timestamp,ping_avg_ms,packet_loss,http_roundtrip_s,dns_ms,download_bytes_per_sec,notes"
  exit 0
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Ping (5 packets, 5s timeout)
PING_OUTPUT=$(ping -c 5 -W 5 8.8.8.8 2>/dev/null)
if [ $? -eq 0 ]; then
  PING_AVG=$(echo "$PING_OUTPUT" | tail -1 | awk -F'/' '{print $5}')
  PING_LOSS=$(echo "$PING_OUTPUT" | grep "packet loss" | awk '{for(i=1;i<=NF;i++) if($i ~ /loss/) print $(i-1)}')
else
  PING_AVG="timeout"
  PING_LOSS="100%"
fi

# HTTP round-trip to Anthropic API
HTTP_TIME=$(curl -o /dev/null -s -w '%{time_total}' --max-time 10 https://api.anthropic.com 2>/dev/null)
if [ $? -ne 0 ]; then
  HTTP_TIME="timeout"
fi

# DNS resolution time
DNS_TIME=$(dig api.anthropic.com +stats 2>/dev/null | grep "Query time" | awk '{print $4}')
if [ -z "$DNS_TIME" ]; then
  DNS_TIME="timeout"
fi

# Download speed (1MB test file)
DL_SPEED=$(curl -o /dev/null -s -w '%{speed_download}' --max-time 30 https://speed.cloudflare.com/__down?bytes=1000000 2>/dev/null)
if [ $? -ne 0 ]; then
  DL_SPEED="timeout"
fi

# Optional notes as argument
NOTES="${1:-}"

echo "$TIMESTAMP,$PING_AVG,$PING_LOSS,$HTTP_TIME,$DNS_TIME,$DL_SPEED,$NOTES"
