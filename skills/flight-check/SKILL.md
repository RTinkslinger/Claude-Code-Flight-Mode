---
name: flight-check
description: Check if the Claude API is accessible from your current network. Tests DNS, HTTPS reachability, geo-IP egress, latency, and download speed. Run at airports or in-flight to verify connectivity.
argument-hint:
user-invocable: true
allowed-tools: Read, Bash
---

# /flight-check

Run the connectivity check suite to determine whether the Claude API is reachable from the current network.

## Steps

### 1. Run the flight check script

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/flight-check.sh"
```

Capture the full output. This script tests DNS resolution, HTTPS reachability, HTTP status codes, latency, geo-IP egress country, and download speed against the Claude API endpoint.

### 2. Run network detection (optional enrichment)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/network-detect.sh"
```

This detects the current WiFi SSID and attempts to classify the network type (airline, airport, hotel, other) and identify the provider.

### 3. Present results to the user

Combine the outputs from both scripts and present a clear, structured report:

```
Flight Check Results
━━━━━━━━━━━━━━━━━━━

Verdict: [GO / CAUTION / BLOCKED / OFFLINE]

Network:
  WiFi: [SSID] ([type]: airline/airport/hotel/other)
  Provider: [if detected]

API Access:
  Reachable: [yes/no]
  Latency: [X]ms
  HTTP Status: [code]

Geo-IP:
  Egress: [city], [country]
  Country Supported: [yes/no]

Network Quality:
  Ping: [X]ms avg
  Download: [X] KB/s
```

### 4. Interpret the verdict

**GO** — API is reachable, latency is acceptable, egress country is supported. Report this and confirm the user is clear to work.

**CAUTION** — API is reachable but conditions are degraded (high latency, slow download, intermittent). Advise the user to activate `/flight-on` for resilience.

**BLOCKED** — API is unreachable due to geo-blocking or network filtering. Provide the geo-blocking explanation below.

**OFFLINE** — No network connectivity at all. DNS fails, no route to host.

### 5. Geo-blocking explanation (when verdict is BLOCKED or country is unsupported)

If the check reveals geo-blocking, explain the following to the user:

**How geo-blocking works on airline/airport WiFi:**

- **Geo-blocking is based on IP egress, not physical location.** Your plane can be over the Atlantic, but the API sees the country where your traffic exits to the internet.
- **Airport WiFi** uses local terrestrial routing. The "country" for geo-blocking purposes is the country the airport is in. If you are at an airport in an excluded country, the API will be blocked.
- **Airline WiFi** uses satellite routing. Traffic goes up to a satellite, down to a ground station, then to the internet. The ground station determines your egress country. Most airline satellite providers (Viasat, Inmarsat, Panasonic Avionics) have ground stations in the US, UK, or EU — so airline WiFi usually works even when flying over or departing from excluded countries.
- **Starlink Aviation** is unpredictable. SpaceX uses inter-satellite links (ISL) that can route traffic to any ground station globally. Your egress country can change mid-flight as the satellite mesh reroutes.

**If on airport WiFi in an excluded country:**

> Airport WiFi routes through the local country's infrastructure, which is excluded from Claude API access. Connect to the airline's onboard WiFi instead — it routes via satellite ground stations, typically in the US, UK, or EU, bypassing the geo-restriction.

**VPN workaround:**

> If airline WiFi is not available or also blocked, use a VPN to route traffic through a supported country. OpenVPN configured over TCP port 443 is recommended — it mimics HTTPS traffic and passes through airline captive portal firewalls that block other VPN protocols (WireGuard/UDP, IPSec). Most commercial VPN apps support this mode in their settings under "protocol" or "stealth mode."
