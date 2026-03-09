# Flight Mode — Airline WiFi Profiles

> **Generated:** 2026-03-09 via Cowork deep research
> **Coverage:** 40+ carriers across Asia, Middle East, Europe, Americas
> **Purpose:** Read by `/flight-on` to calibrate micro-task batch size and commit frequency
> **Last updated:** 2026-03-09

---

## Rating Scale

| Rating | Meaning | Micro-task batch | Commit frequency |
|---|---|---|---|
| EXCELLENT | LEO-equipped (Starlink/Kuiper), sub-100ms latency | Up to 5 queued | Every 4-5 tasks |
| GOOD | Modern HTS Ka/Ku, stable long windows | Up to 3 queued | Every 3-4 tasks |
| USABLE | Standard GEO satellite, periodic drops | 1-2 at a time | Every 2-3 tasks |
| CHOPPY | Legacy GEO, frequent micro-drops | 1 at a time | After every task |
| POOR | Barely functional or no WiFi | 1 task, minimal reads | After every task |
| UNKNOWN | Carrier/route not profiled | Defaults to USABLE | Every 2-3 tasks |

---

## Quick Lookup Table

| Carrier | Rating (domestic) | Rating (long-haul) | Stable Window | Key Note |
|---|---|---|---|---|
| Delta | GOOD | USABLE | 45-90 / 20-40 min | Upload <1 Mbps; free for SkyMiles |
| United (Starlink) | EXCELLENT | — | 60+ min | Check aircraft type |
| United (legacy GEO) | USABLE | USABLE | 20-40 min | Mainline transitioning to LEO |
| American (narrowbody) | USABLE | — | 15-30 min | Re-auth after device sleep |
| American (widebody) | CHOPPY | CHOPPY | 15-30 min | Panasonic hardware |
| JetBlue | GOOD | — | 30-60 min | Free for all passengers |
| Southwest (current) | CHOPPY | — | 10-20 min | Starlink rollout mid-2026 |
| Southwest (Starlink) | EXCELLENT | — | 60+ min | From mid-2026 |
| Alaska (legacy) | CHOPPY | — | 15-30 min | Starlink installs underway |
| Air Canada | GOOD | USABLE | 30-60 min | Free for Aeroplan members |
| Spirit | GOOD | — | 30-60 min | SES-17 satellite; $18 |
| Frontier | POOR | — | — | No WiFi currently |
| Air France | EXCELLENT | EXCELLENT | 60+ min | Starlink fleet; free Flying Blue |
| KLM | GOOD | — | 30-60 min | European routes; free Flying Blue |
| Lufthansa (legacy) | CHOPPY | CHOPPY | 10-20 min | Hardware lottery |
| Lufthansa (Starlink) | EXCELLENT | EXCELLENT | 60+ min | Limited fleet until 2029 |
| Etihad (Amara) | GOOD | GOOD | 30-45 min | New aircraft solid |
| Etihad (legacy) | USABLE | USABLE | 20-40 min | Reliability complaints |
| Emirates | USABLE | USABLE | 20-40 min | Premium tier needed for API |
| Qatar | USABLE | USABLE | 20-40 min | Varies by aircraft type |
| Cathay Pacific | USABLE | USABLE | 20-40 min | 600-900ms latency; 1-2 drops/flight |
| Singapore Airlines | USABLE | USABLE | 20-40 min | Workable; premium cabin complimentary |
| ANA (767 Viasat) | GOOD | — | 30-60 min | Free all classes |
| ANA (777 long-haul) | CHOPPY | CHOPPY | 10-20 min | Hour-long blackouts possible |
| Thai Airways (NSG) | GOOD | GOOD | 30-60 min | Multi-orbit pioneer |
| Thai Airways (legacy) | CHOPPY | CHOPPY | 10-20 min | Un-upgraded fleet |
| Air India | USABLE | USABLE | 20-40 min | Portal login finicky |
| IndiGo | POOR | — | — | No WiFi until late 2025 |
| Ryanair / easyJet / Wizz | POOR | — | — | No viable WiFi |
| Asian LCCs | POOR | POOR | — | Not reliable for API work |

---

## Route Patterns (cross-carrier)

| Route Type | Typical Rating | Notes |
|---|---|---|
| US Domestic | GOOD — EXCELLENT | Dense coverage, short flights, best corridor |
| Transatlantic | GOOD — EXCELLENT | Dense HTS satellite, competitive corridor |
| Transpacific | USABLE | Satellite handoff drops, 1-3 per crossing |
| Europe-Asia | USABLE — CHOPPY | Equatorial segment risk near SE Asia |
| Polar routes | CHOPPY — POOR | Arctic blackout windows; use for offline review |
| Equatorial | CHOPPY — POOR | Worst for satellite physics; legacy antennas fail |

---

## UNKNOWN / Fallback Profile

Use when carrier or route is not listed above.

- **Download:** Assume 5-15 Mbps shared
- **Upload:** Assume <2 Mbps
- **Latency:** Assume 600-900ms
- **Drop pattern:** Assume drops every 20-40 min
- **Rating:** USABLE
- **Stable window:** 20-30 min
- **Dev notes:** Follow standard flight mode protocol. Micro-tasks of 1-2 tool calls. Checkpoint every 2-3 tasks. Git commit every 2-3 tasks.

---

## Detailed Carrier Profiles

Detailed per-carrier information below. Claude reads this section only if the user asks for more detail.

### Delta Air Lines (Viasat Ka-band — GEO)
- **Routes:** US domestic, transatlantic, transpacific
- **Download:** 54 Mbps median (Ookla)
- **Upload:** <1 Mbps (severe bottleneck)
- **Latency:** 600-900ms
- **Drop pattern:** Stable domestically; oceanic handoff gaps on transpacific
- **Fleet:** Most mainline fleet; ~25% of A350s still on older 2Ku
- **Pricing:** Free for SkyMiles members (since 2023)
- **Dev notes:** Download solid. Upload is the killer — avoid large git pushes. Commit locally, push post-flight.

### United Airlines (Starlink LEO + Viasat/Panasonic GEO)
- **Routes:** US domestic, transatlantic, transpacific
- **Download:** 40-220 Mbps (Starlink); variable on legacy GEO
- **Upload:** Strong on Starlink; <1 Mbps on legacy
- **Latency:** <100ms (Starlink); 600-900ms (GEO)
- **Fleet:** Nearly all dual-cabin RJs on Starlink; mainline transitioning (2026)
- **Dev notes:** Starlink RJs are near-ground quality. Mainline GEO widebodies: treat as standard satellite. Check aircraft type.

### American Airlines (Viasat/Intelsat Ka/Ku — GEO)
- **Routes:** US domestic, transatlantic, Latin America
- **Download:** 50 Mbps median; 4.7-7.2 Mbps on free tier
- **Latency:** 600-750ms
- **Drop pattern:** Re-auth required after device sleep (ads + portal)
- **Fleet:** Narrowbodies + dual-class regionals (free); Panasonic widebodies excluded from free
- **Dev notes:** Keep laptop awake — re-auth-after-sleep is brutal. Widebody Panasonic: basic messaging only.

### JetBlue (Viasat Ka — GEO)
- **Download:** 23 Mbps median
- **Latency:** GEO typical (600-900ms)
- **Fleet:** Fleetwide Viasat (all aircraft)
- **Pricing:** Free for all passengers since 2013
- **Dev notes:** Only US carrier with truly free WiFi for everyone. Kuiper LEO upgrade 2027.

### Southwest Airlines (Viasat/Anuvu GEO → Starlink LEO 2026)
- **Download:** ~30 Mbps (feels slow due to latency/packet loss)
- **Drop pattern:** Inconsistent; some users report total page load failures
- **Fleet:** Mixed Viasat/Anuvu; 300+ aircraft getting Starlink by end 2026
- **Dev notes:** Current WiFi unreliable for Claude Code. After mid-2026, check for Starlink aircraft.

### Alaska Airlines (Intelsat 2Ku — GEO → Starlink)
- **Download:** Slow, widely criticized
- **Latency:** 600-1000ms
- **Dev notes:** Legacy 2Ku is painful. Keep micro-tasks extremely atomic. Starlink aircraft will transform this.

### Air Canada (Intelsat 2Ku / Panasonic — GEO)
- **Download:** Streaming quality on 88% of fleet
- **Fleet:** 88% coverage; Q400s adding 2025; long-haul free in 2026
- **Pricing:** Free for Aeroplan members (Bell sponsored)
- **Dev notes:** Solid for Claude Code on North American routes.

### Spirit Airlines (Thales FlytLIVE / SES-17 Ka — GEO)
- **Download:** Strong; handles streaming easily
- **Upload:** Fast for GEO
- **Fleet:** Growing across A320neo fleet
- **Pricing:** $17.99 streaming tier
- **Dev notes:** Sleeper pick. SES-17 delivers genuinely good performance despite being a ULCC.

### Air France (Starlink Ku — LEO)
- **Download:** 40-220 Mbps per aircraft
- **Latency:** <100ms
- **Fleet:** 30% by end-2025; 100% by end-2026
- **Pricing:** Free for Flying Blue members
- **Dev notes:** Best-in-class for coding. Sub-100ms latency = near-normal Claude Code experience.

### KLM (Viasat Amara Ka — GEO multi-layer)
- **Download:** Up to 248 Mbps tested (plane-level)
- **Fleet:** 68 aircraft (A321neo, 737-800, E195-E2)
- **Pricing:** Free for Flying Blue on European flights
- **Dev notes:** Good for European hops. 30-40% passenger uptake may slow during peak.

### Lufthansa Group (Panasonic/Telekom GEO → Starlink LEO)
- **Drop pattern:** Frequent complaints on long-haul; some A320neos lack WiFi entirely
- **Fleet:** Mixed and inconsistent. Starlink rollout H2 2026, full by 2029
- **Dev notes:** Hardware lottery. Pre-2027, treat as CHOPPY unless confirmed Starlink.

### Etihad Airways (Viasat Amara Ka — GEO)
- **Fleet:** A321LR, A350, 787 (expanding)
- **Dev notes:** New Amara aircraft solid. Legacy aircraft a gamble. Multi-orbit LEO coming.

### Emirates
- **Pricing:** Free basic (messaging only); paid streaming tier
- **Dev notes:** Free tier won't support Claude Code. Premium tier needed for API calls.

### Qatar Airways
- **Fleet:** Growing but uneven; newer 787-9s and A350s tend better
- **Dev notes:** Premium cabin may get complimentary access. Performance varies by aircraft.

### Cathay Pacific (Intelsat 2Ku — GEO)
- **Routes:** HKG hub to global destinations
- **Download:** 4-7 Mbps typical (shared)
- **Upload:** 1-3 Mbps
- **Latency:** 600-900ms
- **Drop pattern:** Periodic drops, especially over oceanic segments
- **Dev notes:** Claude Code's ~200 kbps payloads fit within bandwidth. Latency adds ~1-2s per round-trip. Micro-task pattern essential. Expect 1-2 drops per long-haul.

### ANA — All Nippon Airways
- **Fleet:** 767 (Viasat — free, streaming); 777/787/A380 (legacy Panasonic/Inmarsat)
- **Drop pattern:** 777-300ERs: 1-2 hour blackouts on long-haul
- **Dev notes:** Massive variance by subfleet. 767 Viasat excellent. 777 long-haul unreliable. Always check aircraft type.

### Thai Airways (Neo Space Group / SES Open Orbits)
- **Download:** Up to 200 Mbps to aircraft (NSG system)
- **Fleet:** 777, A321neo, 787-9 (rolling out 2025-2026, 80 aircraft total)
- **Pricing:** Free for Premium/Royal Orchid Plus (from May 2025)
- **Dev notes:** Multi-orbit pioneer. NSG-equipped aircraft genuinely good. Verify aircraft.

### Air India (Panasonic / Nelco — GEO)
- **Fleet:** A350, 787-9, select A321neo
- **Pricing:** Free (introductory period)
- **Dev notes:** Portal login finicky — retry multiple times. Adequate for Claude Code when connected.

### Singapore Airlines
- **Fleet:** A350, 787, A380 (varying by subfleet)
- **Pricing:** Paid tiers; complimentary in premium cabins (varies)
- **Dev notes:** Workable but not exceptional.

---

## Technology Quick Reference

| Technology | Orbit | Latency | Best For | Watch Out |
|---|---|---|---|---|
| Starlink | LEO | <100ms | Everything — near-ground quality | Still rolling out |
| Viasat Ka | GEO | 600-900ms | Good download; browsing/streaming | Upload <1 Mbps |
| Intelsat 2Ku | GEO | 600-900ms | Broad coverage | Aging infrastructure |
| Panasonic Ku | GEO | 600-900ms | Legacy reliability | Slow by modern standards |
| Gogo ATG | Ground | <200ms | Low latency; US overland | US-only; max 9.8 Mbps |
| SES-17/Thales | GEO Ka | 600-900ms | High capacity | Limited fleet adoption |
| Amazon Kuiper | LEO | <100ms expected | Next-gen competitor | Launches 2027 |

---

## Upload Speed Warning

Across ALL GEO satellite providers, upload from aircraft is severely constrained (<1-2 Mbps). Claude Code's API payloads (~200 kbps) are fine, but avoid large git pushes, file uploads, or sustained upload bandwidth. **Commit locally, push post-flight.**

---

## Data Sources

Research from: airline press releases, aviation media (TPG, VFTW, OMAAT, Runway Girl, Simple Flying), Ookla speed benchmarks, FlyerTalk, Reddit, satellite operator docs.

**Contributing:** If you've used Claude Code on a flight not profiled here, submit a measurement (see `measurements/` directory template) and we'll add it.
