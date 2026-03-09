# Flight Mode — Airline WiFi Profiles

> **Generated:** 2026-03-09 via Cowork deep research (4 parallel agents)
> **Coverage:** 40+ carriers across Asia, Middle East, Europe, Americas, and LCCs
> **Purpose:** Claude Code reference file — read by `/flight-on` to calibrate behavior
> **Maintainer:** Regenerate via Cowork research session when carriers upgrade fleets

---

## How to Use This File

When `/flight-on` activates, Claude reads this file to find the carrier + route match. The **Rating** field drives micro-task batch size, commit frequency, and context frugality level per the behavioral protocol in FLIGHT_MODE.md.

**If carrier is not listed:** Use the `UNKNOWN` fallback profile at the bottom.

---

## Rating Scale

| Rating | Meaning | Micro-task batch | Commit frequency |
|---|---|---|---|
| EXCELLENT | LEO-equipped (Starlink/Kuiper), sub-100ms latency | Up to 5 queued | Every 4-5 tasks |
| GOOD | Modern HTS Ka/Ku, stable long windows | Up to 3 queued | Every 3-4 tasks |
| USABLE | Standard GEO satellite, periodic drops | 1-2 at a time | Every 2-3 tasks |
| CHOPPY | Legacy GEO, frequent micro-drops, inconsistent | 1 at a time | After every task |
| POOR | Barely functional, long outages, hardware lottery | 1 task, minimal reads | After every task |
| UNKNOWN | Carrier/route not profiled | Defaults to USABLE | Every 2-3 tasks |

---

## North America

### Delta Air Lines (Viasat Ka-band — GEO)
- **Routes:** US domestic, transatlantic, transpacific
- **Download:** 54 Mbps median (Ookla)
- **Upload:** <1 Mbps (severe bottleneck)
- **Latency:** 600-900ms (GEO typical)
- **Drop pattern:** Generally stable domestically; oceanic handoff gaps on transpacific
- **Fleet coverage:** Most mainline fleet; ~25% of A350s still on older 2Ku
- **Pricing:** Free for SkyMiles members (since 2023)
- **Rating:** GOOD (domestic), USABLE (long-haul)
- **Stable window:** 45-90 min domestic; 20-40 min oceanic
- **Dev notes:** Download is solid for pulling code/responses. Upload is the killer — avoid pushing large commits or running tools that need upload bandwidth. Commit locally, push post-flight.

### United Airlines (Starlink LEO + Viasat/Panasonic GEO)
- **Routes:** US domestic, transatlantic, transpacific
- **Download:** 40-220 Mbps (Starlink aircraft); variable on legacy GEO
- **Upload:** Strong on Starlink; <1 Mbps on legacy
- **Latency:** <100ms (Starlink); 600-900ms (GEO)
- **Drop pattern:** Starlink very stable; GEO has oceanic gaps
- **Fleet coverage:** Nearly all dual-cabin regional jets on Starlink; mainline transitioning from GEO to LEO (2026)
- **Pricing:** Varies by aircraft/provider
- **Rating:** EXCELLENT (Starlink RJs), USABLE (legacy mainline)
- **Stable window:** Starlink: 60+ min; GEO: 20-40 min
- **Dev notes:** If you're on a Starlink-equipped regional jet, this is near-ground quality. On mainline GEO widebodies, treat as standard satellite. Check aircraft type before flight.

### American Airlines (Viasat/Intelsat Ka/Ku — GEO)
- **Routes:** US domestic, transatlantic, Latin America
- **Download:** 50 Mbps median (Ookla); 4.7-7.2 Mbps on free tier
- **Upload:** 2.2-4.3 Mbps (free tier); <1 Mbps median overall
- **Latency:** 600-750ms
- **Drop pattern:** Connection drops if device sleeps (requires re-auth + ads); inconsistent activation by tail number
- **Fleet coverage:** Narrowbodies + dual-class regionals (free tier); Panasonic widebodies EXCLUDED from free
- **Pricing:** Free for AAdvantage members (Jan 2026, ad-supported); $30 for non-members/widebodies
- **Rating:** USABLE (narrowbody), CHOPPY (widebody Panasonic)
- **Stable window:** 15-30 min (re-auth friction after sleep)
- **Dev notes:** The re-auth-after-sleep behavior is brutal for Claude Code. Keep your laptop awake. On widebody Panasonic aircraft, expect basic messaging only — not viable for API-dependent coding.

### JetBlue (Viasat Ka — GEO, transitioning to Amazon Kuiper LEO 2027)
- **Routes:** US domestic, Caribbean, transatlantic (limited)
- **Download:** 23 Mbps median (Ookla)
- **Upload:** Not publicly benchmarked; GEO-limited
- **Latency:** GEO typical (600-900ms)
- **Drop pattern:** Generally stable on domestic routes
- **Fleet coverage:** Fleetwide Viasat (all aircraft)
- **Pricing:** Free for all passengers (since 2013) — no loyalty gating
- **Rating:** GOOD
- **Stable window:** 30-60 min
- **Dev notes:** The only US carrier with truly free Wi-Fi for everyone. Speeds are aging but workable for Claude Code's small payloads. Kuiper LEO upgrade in 2027 will be a step change.

### Southwest Airlines (Viasat/Anuvu GEO, transitioning to Starlink LEO 2026)
- **Routes:** US domestic
- **Download:** ~30 Mbps (but feels slow due to latency/packet loss)
- **Upload:** Not benchmarked
- **Latency:** High (GEO); users report "unusable" browsing despite speed numbers
- **Drop pattern:** Inconsistent; some users report total inability to load pages
- **Fleet coverage:** Current: mixed Viasat/Anuvu. 300+ aircraft getting Starlink by end 2026
- **Pricing:** Free for Rapid Rewards members (T-Mobile sponsored)
- **Rating:** CHOPPY (current fleet), EXCELLENT (Starlink aircraft from mid-2026)
- **Stable window:** 10-20 min (current); 60+ min (Starlink)
- **Dev notes:** Current WiFi is unreliable for Claude Code. If flying Southwest after mid-2026, check if your aircraft has Starlink — it'll be a completely different experience.

### Alaska Airlines (Intelsat 2Ku — GEO, transitioning to Starlink)
- **Routes:** US West Coast, Hawaii, transcon
- **Download:** Slow (unquantified but widely criticized)
- **Upload:** Not benchmarked
- **Latency:** 600-1000ms
- **Drop pattern:** High latency makes everything feel sluggish
- **Fleet coverage:** Legacy 2Ku; Starlink installs underway
- **Pricing:** $8 flat rate
- **Rating:** CHOPPY (legacy), EXCELLENT (Starlink when available)
- **Stable window:** 15-30 min
- **Dev notes:** Legacy 2Ku is painful. Keep micro-tasks extremely atomic. Starlink aircraft will transform this.

### Air Canada (Intelsat 2Ku / Panasonic — GEO)
- **Routes:** Canada domestic, transborder, transatlantic, transpacific
- **Download:** Streaming quality on 88% of fleet
- **Upload:** GEO-limited
- **Latency:** GEO typical
- **Drop pattern:** Stable on North American routes; expanding to Q400 turboprops
- **Fleet coverage:** 88% of fleet (May 2025); Q400s adding 2025; long-haul free in 2026
- **Pricing:** Free for Aeroplan members (Bell sponsored)
- **Rating:** GOOD (North America), USABLE (long-haul)
- **Stable window:** 30-60 min
- **Dev notes:** Solid for Claude Code on North American routes. Long-haul performance TBD as free tier rolls out.

### Spirit Airlines (Thales FlytLIVE / SES-17 Ka — GEO)
- **Routes:** US domestic, Caribbean, Latin America
- **Download:** Strong; handles YouTube/TikTok streaming easily
- **Upload:** Fast (for GEO)
- **Latency:** GEO typical but high-capacity satellite reduces congestion effects
- **Drop pattern:** Stable
- **Fleet coverage:** Growing across A320neo fleet
- **Pricing:** $17.99 streaming tier (no day pass)
- **Rating:** GOOD
- **Stable window:** 30-60 min
- **Dev notes:** Sleeper pick. Despite being a ULCC, the SES-17 satellite delivers genuinely good performance. Worth the $18 if coding in flight.

### Frontier Airlines
- **Routes:** US domestic
- **Pricing:** No Wi-Fi currently. Vendor evaluation underway; planned 2026-2027
- **Rating:** POOR (no service)
- **Dev notes:** No in-flight coding possible. Work offline or don't fly Frontier for work trips.

---

## Europe

### Air France (Starlink Ku — LEO)
- **Routes:** European short-haul, transatlantic, global long-haul
- **Download:** 40-220 Mbps per aircraft
- **Upload:** Strong (LEO)
- **Latency:** <100ms
- **Drop pattern:** High consistency; LEO mesh eliminates dead zones
- **Fleet coverage:** E190, A220, A350 first; 30% by end-2025; 100% by end-2026
- **Pricing:** Free for Flying Blue members in all cabins
- **Rating:** EXCELLENT
- **Stable window:** 60+ min
- **Dev notes:** Best-in-class for coding in flight. Sub-100ms latency means Claude Code will feel near-normal. Full Starlink fleet by end 2026.

### KLM Royal Dutch Airlines (Viasat Amara Ka — GEO multi-layer)
- **Routes:** European network
- **Download:** Up to 248 Mbps tested (plane-level); per-user varies
- **Upload:** GEO-limited but high-capacity satellite reduces bottleneck
- **Latency:** GEO typical but improved via KA-SAT + GX5 capacity
- **Drop pattern:** Stable on European routes
- **Fleet coverage:** 68 aircraft (A321neo, 737-800, E195-E2)
- **Pricing:** Free for Flying Blue members on European flights
- **Rating:** GOOD
- **Stable window:** 30-60 min
- **Dev notes:** Good for European hops. Expect 30-40% passenger uptake on free tier — may slow during peak loads.

### Lufthansa Group — Lufthansa / SWISS / Austrian (Panasonic/Telekom GEO → Starlink LEO)
- **Routes:** European short-haul, global long-haul
- **Download:** Legacy FlyNet: slow/inconsistent on long-haul; Starlink (SWISS A220 wet-lease): excellent
- **Upload:** Legacy: very limited; Starlink: strong
- **Latency:** Legacy: high; Starlink: <100ms
- **Drop pattern:** Legacy: frequent complaints on long-haul (FRA-BOM, FRA-CUN); some A320neos lack WiFi entirely
- **Fleet coverage:** Current: mixed and inconsistent. Starlink rollout begins H2 2026, full deployment by 2029
- **Pricing:** Legacy: paid FlyNet. Starlink: free for status + Travel ID customers
- **Rating:** CHOPPY (legacy long-haul), USABLE (legacy short-haul), EXCELLENT (Starlink when available)
- **Stable window:** Legacy: 10-20 min; Starlink: 60+ min
- **Dev notes:** Hardware lottery. Some aircraft have excellent Starlink, others have no WiFi at all. Check your specific aircraft. Pre-2027, treat as CHOPPY unless confirmed Starlink.

---

## Middle East

### Etihad Airways (Viasat Amara Ka — GEO, multi-orbit roadmap)
- **Routes:** Abu Dhabi hub to global destinations
- **Download:** Designed for seamless streaming
- **Upload:** GEO-limited
- **Latency:** GEO typical
- **Drop pattern:** Factory-installed on new deliveries; legacy systems had user complaints about reliability
- **Fleet coverage:** A321LR, A350, Boeing 787 (expanding)
- **Pricing:** Transitioning; legacy had paid tiers with user complaints about transparency
- **Rating:** GOOD (new Amara aircraft), USABLE (legacy)
- **Stable window:** 30-45 min
- **Dev notes:** New Amara-equipped aircraft are solid. Legacy aircraft are a gamble. Multi-orbit LEO integration coming but timeline unclear.

### Emirates
- **Routes:** Dubai hub to global destinations
- **Download:** Free basic Wi-Fi available; premium tier for streaming
- **Latency:** GEO typical
- **Drop pattern:** Generally reliable on established routes
- **Fleet coverage:** A380 and 777 fleets
- **Pricing:** Free basic tier (messaging); paid streaming tier
- **Rating:** USABLE
- **Stable window:** 20-40 min
- **Dev notes:** Free tier is messaging-only — won't support Claude Code. Premium tier needed for API calls. Workable but not optimized for dev workflows.

### Qatar Airways
- **Routes:** Doha hub to global destinations
- **Download:** Variable; "Super Wi-Fi" branding on select aircraft
- **Latency:** GEO typical
- **Drop pattern:** Inconsistent by aircraft type
- **Fleet coverage:** Growing but uneven
- **Pricing:** Paid tiers; some complimentary for premium cabins
- **Rating:** USABLE
- **Stable window:** 20-40 min
- **Dev notes:** Premium cabin passengers may get complimentary access. Performance varies by aircraft — newer 787-9s and A350s tend to be better.

---

## Asia-Pacific

### Cathay Pacific (Intelsat 2Ku — GEO)
- **Routes:** Hong Kong hub to global destinations (HKG-LHR, HKG-JFK, HKG-SIN, etc.)
- **Download:** 4-7 Mbps typical (shared across cabin)
- **Upload:** 1-3 Mbps
- **Latency:** 600-900ms
- **Drop pattern:** Periodic drops, especially over oceanic segments; satellite handoff gaps
- **Fleet coverage:** Most long-haul fleet (A350, 777)
- **Pricing:** Paid tiers (hourly/flight packages)
- **Rating:** USABLE
- **Stable window:** 20-40 min
- **Dev notes:** Claude Code's tiny API payloads (~200 kbps) fit within the bandwidth. Latency is the bottleneck — each API round-trip adds ~1-2 seconds. Micro-task pattern essential. Expect 1-2 drops per long-haul flight.

### ANA — All Nippon Airways (Panasonic/Inmarsat GEO + Viasat on 767)
- **Routes:** Japan domestic, transpacific, Asian regional
- **Download:** Variable; Viasat 767s support streaming; legacy 777s are slow
- **Upload:** GEO-limited
- **Latency:** GEO typical (600-900ms)
- **Drop pattern:** 777-300ERs: 1-2 hour blackouts reported on long-haul; domestic: generally solid
- **Fleet coverage:** 777, 787, A380 (legacy Panasonic/Inmarsat); 767-300ER (Viasat — free, streaming)
- **Pricing:** Viasat 767: free all classes. Legacy: tiered paid access
- **Rating:** GOOD (767 Viasat / domestic), CHOPPY (777 long-haul)
- **Stable window:** Domestic: 30-60 min; 777 long-haul: 10-20 min with blackout risk
- **Dev notes:** Massive variance by subfleet. 767 Viasat is excellent. 777 long-haul is unreliable — plan for hour-long outages. Always check aircraft type.

### Thai Airways (Neo Space Group / SES Open Orbits — GEO+MEO)
- **Routes:** Bangkok hub to global destinations
- **Download:** Up to 200 Mbps to aircraft (NSG system)
- **Upload:** Strong (multi-orbit)
- **Latency:** Lower than pure GEO (MEO component)
- **Drop pattern:** Mixed in 2024; improving with NSG retrofits in 2025-2026
- **Fleet coverage:** 777, A321neo, 787-9 (rolling out 2025-2026, 80 aircraft total)
- **Pricing:** Free for Premium/Royal Orchid Plus members (from May 2025)
- **Rating:** GOOD (NSG-equipped), CHOPPY (legacy/un-upgraded)
- **Stable window:** NSG: 30-60 min; Legacy: 10-20 min
- **Dev notes:** Multi-orbit pioneer. NSG-equipped aircraft should be genuinely good. But 2024-era aircraft without upgrades are inconsistent. Verify aircraft.

### Air India (Panasonic / Nelco — GEO)
- **Routes:** India domestic, international
- **Download:** 720p YouTube streaming reported on equipped aircraft
- **Upload:** GEO-limited
- **Latency:** GEO typical
- **Drop pattern:** Occasional portal login failures; bandwidth limits
- **Fleet coverage:** A350, 787-9, select A321neo (first Indian airline with domestic Wi-Fi, Jan 2025)
- **Pricing:** Free (introductory period)
- **Rating:** USABLE (equipped aircraft)
- **Stable window:** 20-40 min
- **Dev notes:** Portal login can be finicky — retry multiple times. When connected, adequate for Claude Code's lightweight payloads. Free tier may get congested.

### IndiGo
- **Routes:** India domestic, short-haul international
- **Fleet coverage:** No current Wi-Fi service. Planned launch Nov 2025 for Business Class (~25 aircraft)
- **Rating:** POOR (no service until late 2025)
- **Dev notes:** No in-flight coding possible currently. Plan offline work.

### Singapore Airlines
- **Routes:** Singapore hub to global destinations
- **Download:** Streaming quality on newer aircraft
- **Latency:** GEO typical
- **Drop pattern:** Generally reliable
- **Fleet coverage:** A350, 787, A380 (varying by subfleet)
- **Pricing:** Paid tiers; complimentary in premium cabins (varies)
- **Rating:** USABLE
- **Stable window:** 20-40 min
- **Dev notes:** Workable but not exceptional. Premium cabin complimentary access may save hassle.

---

## Low-Cost Carriers (Global)

### Ryanair / easyJet / Wizz Air (European LCCs)
- **Routes:** European short-haul
- **Fleet coverage:** Limited or no Wi-Fi on most aircraft
- **Rating:** POOR
- **Dev notes:** Don't plan to code. These flights are short enough to work offline.

### AirAsia / Scoot / Cebu Pacific (Asian LCCs)
- **Routes:** Southeast Asian short-haul and medium-haul
- **Fleet coverage:** Variable; some aircraft have basic connectivity
- **Rating:** POOR to CHOPPY
- **Dev notes:** Not reliable for API-dependent work. Offline-first or don't count on it.

---

## Route-Based Patterns (Cross-Carrier)

Regardless of airline, certain route types have predictable WiFi behavior due to satellite physics:

### Transatlantic (JFK-LHR, etc.)
- **Pattern:** Dense HTS satellite coverage; highly competitive corridor
- **Typical experience:** GOOD to EXCELLENT on modern aircraft
- **Dev notes:** Best oceanic corridor for coding. Streaming feasible. Keep uploads conservative.

### Transpacific (LAX-NRT, SFO-SIN, etc.)
- **Pattern:** Long overwater; multiple satellite spot beam handoffs
- **Typical experience:** USABLE with periodic handoff drops
- **Dev notes:** Schedule large pulls mid-cruise. Build retries around handoff windows. Expect 1-3 drops per crossing.

### Europe-Asia (LHR-SIN, FRA-BOM, etc.)
- **Pattern:** Mix of overland + maritime; equatorial skew risk near SE Asia
- **Typical experience:** USABLE to CHOPPY depending on hardware
- **Dev notes:** Chunk code pushes. Avoid long-lived connections. Equatorial segments are the riskiest.

### US Domestic
- **Pattern:** Dense coverage (satellite + ATG); short flights
- **Typical experience:** GOOD to EXCELLENT
- **Dev notes:** Best domestic coding environment. Short flights = less exposure to drops.

### Polar Routes (JFK-HKG, ORD-DEL, etc.)
- **Pattern:** Extreme low elevation angles to GEO satellites; improving with Arctic Ka and LEO
- **Typical experience:** CHOPPY to POOR over polar segments
- **Dev notes:** Expect blackout windows over the Arctic. Use these for offline review/planning. Resume Claude Code when back in satellite coverage.

### Equatorial Routes (LAX-LIM, SIN-SYD, etc.)
- **Pattern:** High skew angles cause adjacent satellite interference; legacy antennas suffer up to 76% outage
- **Typical experience:** CHOPPY to POOR on legacy; USABLE on 2Ku/ESA-equipped aircraft
- **Dev notes:** The worst corridor for satellite WiFi due to physics. Modern phased-array antennas (2Ku, ESA) mitigate this. Legacy gimbaled antennas will fail here.

---

## Technology Quick Reference

| Technology | Orbit | Latency | Best For | Watch Out For |
|---|---|---|---|---|
| **Starlink** | LEO | <100ms | Everything — near-ground quality | Still rolling out; not all aircraft have it yet |
| **Viasat Ka** | GEO | 600-900ms | Good download; adequate for browsing/streaming | Upload <1 Mbps; high latency kills interactive feel |
| **Intelsat 2Ku** | GEO | 600-900ms | Broad coverage; works on most routes | Latency-dependent tasks suffer; aging infrastructure |
| **Panasonic Ku** | GEO | 600-900ms | Legacy reliability; wide fleet coverage | Slow by modern standards; not competitive |
| **Gogo ATG** | Ground towers | <200ms | Low latency; US overland | US-only; max 9.8 Mbps per aircraft; limited to overland |
| **SES-17/Thales** | GEO Ka | 600-900ms | High capacity single satellite | Limited fleet adoption |
| **NSG/SES Open Orbits** | GEO+MEO | Lower than pure GEO | Multi-orbit; good capacity + reduced latency | Early rollout; limited to Thai Airways currently |
| **Amazon Kuiper** | LEO | <100ms (expected) | Next-gen LEO competitor to Starlink | Launches 2027; JetBlue is first airline customer |

---

## Upload Speed Warning

**Critical for developers:** Across ALL GEO satellite providers, upload from aircraft is severely constrained:

- Viasat Ka: max 2 Mbps from aircraft
- Most GEO systems: <1 Mbps effective upload under load
- Starlink LEO: significantly better but still shared across cabin

**Claude Code impact:** Claude Code's API payloads are tiny (~200 kbps), so this is usually fine. But avoid: large git pushes, file uploads, or any tool that needs sustained upload bandwidth. Commit locally, push post-flight.

---

## UNKNOWN / Fallback Profile

Use when carrier or route is not listed above.

- **Download:** Assume 5-15 Mbps shared
- **Upload:** Assume <2 Mbps
- **Latency:** Assume 600-900ms
- **Drop pattern:** Assume drops every 20-40 min
- **Rating:** USABLE
- **Stable window:** 20-30 min
- **Dev notes:** Follow standard flight mode protocol. Micro-tasks of 1-2 tool calls. Checkpoint after every task. Git commit every 2-3 tasks. Context frugality on.

---

## Data Sources

This file was generated from 4 parallel deep research agents covering:
1. **Asian carriers** — ANA, Thai Airways, Air India, IndiGo, Cathay Pacific, Singapore Airlines
2. **Middle East + European carriers** — Emirates, Qatar, Etihad, Air France, KLM, Lufthansa Group
3. **American carriers + LCCs** — Delta, United, American, JetBlue, Southwest, Alaska, Spirit, Air Canada
4. **Technology & route patterns** — Satellite systems, orbit physics, route-specific performance drivers

Research draws from: airline press releases, aviation media (The Points Guy, View from the Wing, One Mile at a Time, Runway Girl, Simple Flying), Ookla speed benchmarks, FlyerTalk forums, Reddit communities, satellite operator documentation (Viasat, Intelsat, Panasonic, Starlink).

**Last updated:** 2026-03-09
**Next refresh:** Before next trip, or when major fleet upgrades occur (Starlink rollouts, Kuiper launch, etc.)
