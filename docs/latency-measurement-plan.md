# Latency & Connectivity Measurement Plan

**Purpose:** Capture real in-flight network data to inform V2 auto-detection and validate WiFi profiles.
**Status:** Planning — measurements begin on current Cathay Pacific HKG-LAX flight.

---

## Why Measure

1. **Validate profiles** — confirm Cathay Pacific USABLE rating matches reality
2. **Calibrate auto-detection thresholds** — V2 feature: auto-suggest flight mode when latency > Xms
3. **Refine context monitor** — correlate tool call timing with network conditions
4. **Community data** — published measurements help other users calibrate expectations

---

## What to Measure

### Real-Time Metrics (during flight)

| Metric | How | Frequency |
|---|---|---|
| **Ping latency** | `ping -c 5 8.8.8.8` | Every 15-30 min |
| **DNS resolution** | `dig api.anthropic.com +stats` | Every 30 min |
| **HTTP round-trip** | `curl -o /dev/null -s -w '%{time_total}\n' https://api.anthropic.com` | Every 15-30 min |
| **Download speed** | `curl -o /dev/null -s -w '%{speed_download}\n' https://speed.cloudflare.com/__down?bytes=1000000` | Every 30 min |
| **Connection drops** | Manual log: timestamp + duration of outage | On every drop |
| **Claude Code tool call timing** | Note wall-clock time for a Read or Bash call | Every few tasks |

### Session-Level Metrics (logged in .flight-state.md)

| Metric | Description |
|---|---|
| **Total session duration** | Start → end timestamp |
| **Number of drops** | Count of WiFi interruptions |
| **Drop durations** | How long each outage lasted |
| **Tool calls completed** | Total before session end |
| **Checkpoint count** | How many times .flight-state.md was updated |
| **Recovery count** | How many times session was recovered from .flight-state.md |

---

## Measurement Script

Save as `scripts/measure-latency.sh` in the plugin (for users to run during flights):

```bash
#!/bin/bash
# Flight Mode Latency Measurement
# Run periodically during flight to capture network conditions
# Usage: bash measure-latency.sh >> flight-measurements.csv

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Ping (5 packets)
PING_RESULT=$(ping -c 5 -W 5 8.8.8.8 2>/dev/null | tail -1)
if [ $? -eq 0 ]; then
  PING_AVG=$(echo "$PING_RESULT" | awk -F'/' '{print $5}')
  PING_LOSS=$(ping -c 5 -W 5 8.8.8.8 2>/dev/null | grep "packet loss" | awk '{print $7}')
else
  PING_AVG="timeout"
  PING_LOSS="100%"
fi

# HTTP round-trip to Anthropic API
HTTP_TIME=$(curl -o /dev/null -s -w '%{time_total}' --max-time 10 https://api.anthropic.com 2>/dev/null || echo "timeout")

# DNS resolution
DNS_TIME=$(dig api.anthropic.com +stats 2>/dev/null | grep "Query time" | awk '{print $4}' || echo "timeout")

# Download speed (1MB test)
DL_SPEED=$(curl -o /dev/null -s -w '%{speed_download}' --max-time 30 https://speed.cloudflare.com/__down?bytes=1000000 2>/dev/null || echo "timeout")

echo "$TIMESTAMP,$PING_AVG,$PING_LOSS,$HTTP_TIME,$DNS_TIME,$DL_SPEED"
```

**CSV header:** `timestamp,ping_avg_ms,packet_loss,http_roundtrip_s,dns_ms,download_bytes_per_sec`

---

## Data Collection Format

### Per-Flight Log

Save as `measurements/YYYY-MM-DD-CARRIER-ROUTE.md`:

```markdown
# Flight Measurement: [Carrier] [Route]
**Date:** YYYY-MM-DD
**Aircraft:** [type if known]
**WiFi provider:** [if identifiable from portal]
**Seat/cabin:** [economy/business — may affect experience]
**Flight duration:** X hours

## Latency Samples
| Time (UTC) | Ping avg (ms) | Loss % | HTTP RT (s) | DNS (ms) | DL speed |
|---|---|---|---|---|---|
| 14:30 | 680 | 0% | 1.2 | 45 | 450KB/s |
| 15:00 | 720 | 20% | 2.1 | 120 | 280KB/s |
| 15:15 | timeout | 100% | timeout | timeout | — |
| 15:22 | 690 | 0% | 1.4 | 50 | 420KB/s |

## Drop Log
| Start (UTC) | End (UTC) | Duration | Notes |
|---|---|---|---|
| 15:12 | 15:20 | 8 min | Satellite handoff over Pacific |

## Claude Code Observations
- Tool call wall-clock time: ~2-4s per Read, ~3-5s per Edit
- Session dropped at 15:12, recovered at 15:22 from .flight-state.md
- Total micro-tasks completed: X
- Recovery was [smooth/had issues because...]

## Profile Validation
- Listed rating: USABLE
- Observed rating: [USABLE/better/worse]
- Recommended adjustment: [none / upgrade to GOOD / downgrade to CHOPPY]
```

---

## V2 Auto-Detection Thresholds (Draft)

Based on collected data, calibrate these thresholds for automatic flight mode suggestion:

| Condition | Action |
|---|---|
| Latency > 500ms for 3+ consecutive API calls | Suggest: "Network latency is high. Want to activate flight mode?" |
| Packet loss > 10% over 5 pings | Warn: "Unstable connection detected." |
| Connection timeout (any API call) | Warn: "Connection dropped. Flight mode recommended." |
| Latency < 100ms consistently | Suggest deactivation if flight mode is active |

**Implementation approach (V2):**
- SessionStart hook runs a quick latency check
- If thresholds met, injects suggestion into Claude's context
- User confirms activation (no auto-activate without consent)

---

## Current Flight: Cathay Pacific HKG-LAX (2026-03-09)

Measurements directory: `measurements/2026-03-09-cathay-hkg-lax.md`

Capture data points during the plugin build session. This flight IS the first test case.
