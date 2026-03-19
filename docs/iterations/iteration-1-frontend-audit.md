# Iteration 1 — Frontend Audit: Dashboard HTML Template

**Date:** 2026-03-18
**File under review:** `templates/dashboard.html` (432 lines, ~15KB)
**Reviewer scope:** Visual design, functionality, code quality, bugs, missing features, redesign proposal

---

## 1. Visual Design Review

### Color Scheme

The dark theme (`--bg: #0a0e17`, `--card: #0f172a`) is an excellent choice for in-flight use. The dark background reduces glare in cabin lighting, minimizes screen brightness reflection on windows, and reduces eye strain during long sessions. The palette is Tailwind Slate-derived, which is cohesive and well-tested.

**Strengths:**
- Signal color mapping is intuitive: green (>75%), yellow (55-75%), orange (30-55%), red (<30%), gray (0%) — line 117-123
- Card borders (`--border: #1e293b`) provide subtle separation without being distracting
- Cyan accent (`--cyan: #38bdf8`) for the flight code and elapsed timer gives a cockpit instrument feel

**Issues:**
- **P2** The stale banner (line 44) uses `#ef444422` background with `var(--red)` text — red on near-black may not meet WCAG AA contrast for the banner text at 12px. Computed contrast of `#ef4444` on `#0a0e17` is approximately 4.7:1 which technically passes for normal text but is marginal. At 12px font-size, this qualifies as "small text" requiring 4.5:1 — barely passing.
- **P3** The dim color `--dim: #475569` is used for all card titles and labels (lines 29, 33). Contrast against `--card: #0f172a` is approximately 3.4:1 — **fails WCAG AA** for the 10-11px text sizes used. These labels are important for comprehension.
- **P3** The muted color `--muted: #94a3b8` on `--card` background is approximately 5.8:1 — passes, but the sub-text at 11px (`.status-sub`, line 35) is borderline readable in a vibrating aircraft cabin.

### Typography

JetBrains Mono throughout (line 12) is a **strong choice** for this use case:
- Monospace provides tabular alignment for numeric data (latency values, percentages, timestamps)
- `font-variant-numeric: tabular-nums` on `.elapsed` (line 24) ensures the timer doesn't jitter
- The font is legible at small sizes due to its generous x-height

**Issues:**
- **P2** JetBrains Mono is loaded from Google Fonts (line 8) via a network request. On poor in-flight WiFi, this font load may fail or take 10+ seconds. There is no `font-display: swap` or `font-display: fallback` specified in the CSS link. If the font fails to load, the browser will use the monospace fallback but may block rendering for up to 3 seconds (FOIT) on some browsers.
- **P3** The Google Fonts preconnect (line 7) is present, which helps, but there is no `crossorigin` attribute: should be `<link rel="preconnect" href="https://fonts.googleapis.com" crossorigin>` plus a preconnect to `fonts.gstatic.com`.
- **P3** Everything is monospace — even the route description ("Delta · Gogo") and tooltips. A sans-serif for prose text (airline name, notes) would improve readability for non-numeric content.

### Information Hierarchy

The layout follows a logical top-to-bottom priority:
1. Header: Flight identity + rating + elapsed time
2. Charts: Timeline (predicted) + Latency (live)
3. Status cards: API status, current phase, next event, session stats
4. Drop log: Detailed event history

**Issues:**
- **P1** The "Session Stats" card (lines 95-98) showing `XX% ctx` and tool call counts is Claude-specific internal data. A real user monitoring WiFi connectivity does not need context percentage and file reads. This card should show connection stats instead (uptime %, total drops, average latency).
- **P2** The charts section (line 27) uses `grid-template-columns: 1fr` — both charts are full-width stacked. On wide screens (1440px+), the timeline and latency charts could sit side by side, making better use of horizontal space.
- **P3** No visual grouping distinguishes "predicted route data" (timeline) from "live measured data" (latency chart + status cards). A subtle section divider or label would help.

### Visual Density and Responsiveness

- **P2** The only responsive breakpoint is at 768px (line 45), which changes the status row to 2 columns and the header to column layout. There is no breakpoint for very small screens (<480px) or very large screens (>1440px).
- **P2** At 768px and below, the SVG charts maintain their 900-unit viewBox but the containing card has 16px padding. On a 375px phone screen, the chart labels (9px font-size in SVG units) will be approximately 3.75px rendered — completely illegible.
- **P3** No `max-width` on the body or main container. At ultrawide resolutions (2560px), the content stretches edge to edge, which is poor for readability.

---

## 2. Functionality Review

### SVG Timeline Chart (renderTimeline, lines 156-237)

**Strengths:**
- Background zones with color bands show signal quality regions at a glance (lines 168-171)
- Weak zone overlay with labeled "WEAK ZONE" text (lines 174-178) is immediately scannable
- "NOW" marker with dashed line and triangle indicator (lines 209-214) provides real-time position awareness
- Gradient fill under the signal line (lines 197-199) adds visual weight without clutter

**Issues:**
- **P1** The `<defs>` block for `linearGradient` (line 199) is rendered inside the SVG content area, not in a proper `<defs>` section at the top of the SVG. While browsers tolerate this, it is placed after the `<polygon>` that references it — technically the gradient should be defined before use. More critically, if `renderTimeline()` is called multiple times (it is, every 1 second per line 426), the SVG accumulates duplicate `<defs>` blocks because `svg.innerHTML = html` replaces everything each time. This is not a memory leak per se (innerHTML replacement clears old DOM), but it is wasteful re-rendering.
- **P1** `renderTimeline()` is called every 1 second via `setInterval` (line 426) to update the "NOW" marker. This rebuilds the entire SVG innerHTML 86,400 times per day. The waypoint tooltip event listeners (lines 224-236) are re-attached every second, creating and garbage-collecting thousands of event listener objects per minute. Only the "NOW" marker position changes — the rest of the chart is static until route data changes.
- **P2** The tooltip positioning (lines 229-232) uses `getBoundingClientRect()` and multiplies by scale factors, but positions relative to `rect.left` and `rect.top` — these are viewport-relative coordinates. If the page is scrolled (possible on mobile), the tooltip will be mispositioned. Should use `pageX`/`pageY` from the mouse event or account for `window.scrollX`/`scrollY`.
- **P2** Waypoint dots have `r="4"` (line 205) in SVG coordinate space. On a phone screen where the 900-unit viewBox is compressed to ~340px, each dot is approximately 1.5px radius — nearly impossible to tap or hover on touch devices.

### SVG Latency Chart (renderLatency, lines 239-313)

**Strengths:**
- Dual-line display (Ping vs HTTP) with distinct colors (cyan vs purple) is clear
- Latest measurement highlighted with dots (lines 272-277)
- Trend indicator with directional arrows (lines 301-312) provides at-a-glance direction

**Issues:**
- **P1** If `m.http_ms` or `m.ping_ms` is `undefined` or `null`, the yScale function will produce `NaN`, and the polyline `points` attribute will contain `NaN` values, causing the line to not render at all. The data shape from `context-monitor.sh` sets `PING_MS=-1` and `HTTP_MS=-1` on failure (line 91-93 of context-monitor.sh). Negative values will render below the chart area (yScale maps them to `cy + ch + something`), producing a visual spike downward that extends beyond the viewBox. The `maxLatency` calculation (line 249) uses `Math.max(2000, ...)` which would correctly ignore `-1` values, but the polyline still plots them.
- **P2** The X-axis labels (lines 280-286) use `new Date(ms[idx].timestamp)` which assumes valid ISO timestamps. If `timestamp` is null or malformed, this will produce "Invalid Date" and the label will show "NaN:NaN".
- **P2** The trend calculation (lines 302-312) compares the average of the last 3 measurements to the average of measurements 4-6. With only 3 measurements total, `older` will be an empty array (`.slice(-6, -3)` on a 3-element array returns empty). The check `if (older.length > 0)` handles this correctly, but the 100ms threshold for "degrading" vs "improving" seems arbitrary — on satellite WiFi where baseline latency is 500-900ms, a 100ms change is normal fluctuation, not a meaningful trend.

### Status Cards (updateStatusCards, lines 315-368)

**Strengths:**
- Current phase detection by iterating waypoints in reverse (lines 333-336) correctly finds the most recent passed waypoint
- Next event logic handles weak zone proximity, weak zone exit, and general phase changes (lines 342-366)

**Issues:**
- **P1** The `statusClass` function (lines 130-132) returns `'blocked'` for anything that is not `'GO'` or `'CAUTION'`. The API status values from `context-monitor.sh` are: `GO`, `CAUTION`, `BLOCKED`, `OFFLINE` (lines 113-125 of context-monitor.sh). Both `BLOCKED` and `OFFLINE` map to the `blocked` CSS class (red), which is correct, but the dashboard displays the raw status text "OFFLINE" or "BLOCKED" — these need different visual treatment (OFFLINE could be gray, BLOCKED is red).
- **P2** The `egressInfo` (line 320) shows city/country data, but `context-monitor.sh` always writes empty strings for `egress_country` and `egress_city` (lines 166-167 of context-monitor.sh). This status sub-line will always show "—". The geo data is never populated in the current pipeline.

### Tooltip Implementation

**Issues:**
- **P2** The tooltip (line 109) is positioned with `position: absolute` but is a child of `<body>`. When the user hovers over waypoint dots, the tooltip appears at viewport-relative coordinates (lines 231-232). This means on mobile or if the page scrolls, the tooltip may appear off-screen or clipped.
- **P2** Tooltips only exist for waypoint dots in the timeline chart. The latency chart has no tooltip — hovering over data points gives no feedback. Users cannot see individual measurement values.
- **P3** No tooltip for the "WEAK ZONE" overlay — users cannot get details about what the weak zone means without inspecting the source.

### Drop Log Table (renderDrops, lines 370-381)

**Issues:**
- **P2** The `packet_loss` comparison `d.packet_loss != null` (line 379) uses loose inequality. If `packet_loss` is `0`, this evaluates to `true` and displays "0%", which is correct. But if `packet_loss` is the string `"0"`, it would also work due to loose comparison. The data from `context-monitor.sh` always writes numeric values, so this is not a current bug but is fragile.
- **P3** The `peak_latency_ms > 5000` threshold (line 379) for red vs yellow coloring is hardcoded. This threshold should arguably be configurable or relative to the baseline latency for the route.
- **P3** The drop log has no pagination or scrolling constraint. If there are many drops (unlikely given the 10-drop cap in context-monitor.sh), the table would push the page layout down.

### Auto-Refresh and Stale Detection

**Strengths:**
- Stale detection (lines 389-400) with a 30-second threshold and visual banner is well-implemented
- The refresh dot color changes from green to red when stale — good visual indicator
- `lastFetchOk` tracking (line 113, updated at line 414) is clean

**Issues:**
- **P2** `fetchRoute()` is only called once at `init()` (line 423) and never refreshed. If the route data is initially empty (dashboard starts before activation), the dashboard will never re-fetch route data. It should be on a longer interval (e.g., every 60 seconds) or at least re-fetched when live data arrives and route data is still null.
- **P2** The 1-second `setInterval` (line 426) calls `renderTimeline()` every second. This is expensive for a static chart where only the "NOW" marker position changes. See the performance section under SVG Timeline above.

---

## 3. Code Quality

### JavaScript Structure

**Strengths:**
- The `$` shorthand (line 112) is idiomatic and reduces verbosity
- Function separation is clean: `renderHeader`, `renderTimeline`, `renderLatency`, `updateStatusCards`, `renderDrops`, `updateElapsed`, `checkStale`
- Constants for chart dimensions (`P`, `LP` on lines 114-115) prevent magic numbers in rendering code

**Issues:**
- **P1** Two `setInterval` calls (lines 425-426) are created but never stored or cleaned up. If this page is ever used in a SPA context or if `init()` is called twice, intervals will stack. In the current use case (standalone page with auto-refresh), this is not an active bug because the page lifecycle is tied to the tab lifecycle. But it violates best practice.
- **P2** Global mutable state: `routeData`, `liveData`, `lastFetchOk` (line 113) are module-level globals. No encapsulation. If any fetch callback interleaves with a render function mid-update, there could be inconsistent reads (unlikely in practice with JS single-threaded event loop, but the code provides no guarantees about the shape of these objects).
- **P2** The `init()` function (lines 422-427) uses `await fetchRoute()` then `await fetchLive()` sequentially. These could run in parallel with `Promise.all([fetchRoute(), fetchLive()])` for faster initial load.
- **P3** No TypeScript, no JSDoc, no type annotations. The data shapes expected by each function are implicit. The `routeData` shape (flight, airline, route, provider, rating, duration_hours, takeoff_time, waypoints, weak_zone) is never documented in the code.

### CSS Architecture

**Strengths:**
- CSS custom properties (line 11) for the full color palette — easy to theme
- Minimal CSS with no framework dependency
- No unused styles detected

**Issues:**
- **P2** All CSS is in a single `<style>` block with minified selectors (line 10 onwards). While this is fine for a single-file template, the aggressive minification (one rule per line, properties jammed together) makes it hard to maintain. Some rules have inconsistent formatting — `.go{color:...}` vs `.badge-excellent{background:...;color:...;border:...}`.
- **P3** No CSS containment (`contain: layout style`) on the chart cards, which could help browser rendering performance when the SVG content changes frequently.
- **P3** The tooltip has `z-index: 10` (line 43) but nothing else uses z-index. The value is arbitrary and has no stacking context rationale.

### Error Handling

**Issues:**
- **P1** Both `fetchRoute()` and `fetchLive()` (lines 402-420) have empty catch blocks with comments saying "WiFi down — degrade gracefully". This silently swallows all errors including JSON parse failures, CORS issues, and network timeouts. At minimum, a `console.warn` would aid debugging. More importantly, there is no retry logic — if the initial fetch fails, the dashboard shows placeholder "—" values forever until a manual refresh.
- **P2** The `renderTimeline()` function (line 157) checks `if (!routeData) return` but does not check if `routeData.waypoints` exists. If `routeData` is `{}` (which is the initial value written by `dashboard-server.sh` at line 71), `routeData` is truthy but `routeData.waypoints` is `undefined`, causing `wp.length` to throw `TypeError: Cannot read properties of undefined`.

### DOM Manipulation

- **P2** `svg.innerHTML = html` (lines 221, 298) triggers full re-parse of the SVG content. For the latency chart that updates every 10 seconds, this is acceptable. For the timeline chart that updates every 1 second, this is wasteful. The SVG DOM tree is destroyed and rebuilt 86,400 times/day, including re-parsing gradient definitions, re-creating circle elements, and re-attaching event listeners.

---

## 4. Missing Features Assessment

### What a "best in class" flight connectivity dashboard should have:

| Feature | Current State | Importance |
|---------|--------------|------------|
| **Connection quality score** | Rating badge only (EXCELLENT/USABLE/etc) — binary, no numeric score | High — should show a computed 0-100 score based on recent measurements |
| **Historical trend sparkline** | Latency chart shows last 60 points | Medium — a mini-chart in each status card would add density |
| **Alert/notification system** | Stale banner only | Medium — should alert on: entering weak zone, API unreachable, high packet loss |
| **Export/share** | None | Low — screenshot or JSON export of session data for post-flight analysis |
| **Session summary** | Session stats card shows tool calls | High — should show: session duration, total uptime %, drops count, avg latency, best/worst periods |
| **Mobile experience** | Single breakpoint at 768px | High — dashboard is most likely viewed on a phone during flight |
| **Offline indicator** | Stale banner after 30s | Medium — should show time since last successful measurement, not just "connection lost" |
| **Map visualization** | None | Medium — a simple SVG map showing the route and current position would add spatial context |
| **Dark/light toggle** | Dark only | Low — dark is correct for in-flight, but some users may prefer light |
| **Keyboard navigation** | None | Low — not critical for a monitoring dashboard |
| **Touch-friendly controls** | None — dots are too small, no tap interactions | High for mobile |
| **Data table view** | Drop log only | Medium — raw measurement data should be viewable |
| **Connection speed estimate** | None | High — latency alone doesn't tell users if downloads/uploads will work |
| **Sound/vibration alerts** | None | Low — cabin noise makes this impractical |
| **Fullscreen mode** | None | Low — nice-to-have for phone screens |

---

## 5. Bug Identification

### BUG-1: Empty waypoints array crashes renderTimeline (P0)

**Location:** Lines 159, 193, 197
**Trigger:** `route-data.json` has `"waypoints": []` (which happens when the flight-on-lookup.sh finds no matching corridor — line 149 of that script sets `waypoints = []`)

When `wp = routeData.waypoints` is `[]`:
- Line 193: `if (wp.length > 1)` — skipped, no polyline drawn. OK.
- Line 197: `wp[0]` is `undefined`, `wp[wp.length-1]` is `undefined` — no crash because this block is inside the `if (wp.length > 1)` guard. OK.
- Line 203: `wp.forEach(...)` — iterates zero times. OK.
- Lines 333-336 in `updateStatusCards`: `let current = wp[0]` — sets `current` to `undefined`. Line 337: `current.phase` throws `TypeError: Cannot read properties of undefined (reading 'phase')`.

**Impact:** If the route has no waypoints, the status cards crash on every update (every 1 second).

### BUG-2: null takeoff_time causes NaN elapsed time (P0)

**Location:** Lines 139-142, 383-387
**Trigger:** `route-data.json` has `"takeoff_time": null` (which is the default — line 190 of `flight-on-lookup.sh` sets `"takeoff_time": None`)

When `routeData.takeoff_time` is `null`:
- `new Date(null).getTime()` returns `0` (epoch)
- `Date.now() - 0` = current timestamp in milliseconds
- `elapsedHours()` returns ~492,849 hours (time since epoch)
- The "NOW" marker (line 210) `eh >= 0 && eh <= dur` — `eh` is ~493K hours, `dur` is ~13 hours, so condition is false. The NOW marker doesn't render. This is cosmetically wrong but not a crash.
- `fmtTime(Math.max(0, sec))` on line 386 — `sec` is ~1.77 billion. `Math.floor(1774656000/3600)` = 492960 hours. The elapsed timer shows `492960:00:00` or similar nonsense.

**Impact:** The elapsed timer shows an absurd value from the moment the dashboard loads until a real takeoff_time is provided.

### BUG-3: Negative latency values render below the chart (P1)

**Location:** Lines 249, 265-268
**Trigger:** `live-data.json` measurements with `ping_ms: -1` or `http_ms: -1` (the "offline" sentinel value from context-monitor.sh)

When measurement values are `-1`:
- `maxLatency` (line 249) uses `Math.max(2000, ...)`. Since `-1 < 2000`, the max stays at 2000. Correct.
- `yScale(-1)` = `cy + ch - (-1/2000) * ch` = `cy + ch + 0.0005 * ch` — slightly below the bottom of the chart.
- The polyline will have points that extend below the viewBox boundary. The SVG clips to the viewBox, so the line will appear to drop to the bottom edge and stick there.

**Impact:** Offline measurements show as spikes to the bottom of the chart instead of being filtered out or shown as gaps.

### BUG-4: Route string split assumes dash separator (P2)

**Location:** Line 148, 365
**Trigger:** Route string format is "LAX-JFK" but `replace('-', ' -> ')` (line 148) only replaces the first dash. If an airport code contained a dash (unlikely but possible with ICAO codes), only the first dash is replaced.

More concerning: line 365 uses `routeData.route.split('-')[1]` to get the destination. If the route is null or uses a different separator, this returns `undefined`.

**Impact:** Minor — route display may show raw format instead of formatted version.

### BUG-5: Tooltip positioning ignores scroll offset (P2)

**Location:** Lines 229-232
**Trigger:** User scrolls the page (possible on mobile when the full dashboard doesn't fit the viewport) and hovers over a waypoint dot.

The tooltip position is calculated using `rect.left` and `rect.top` from `getBoundingClientRect()`, which are viewport-relative. The tooltip has `position: absolute`, which positions relative to the nearest positioned ancestor (in this case, `<body>` with no positioning). On a scrolled page, viewport coordinates and document coordinates diverge.

**Impact:** Tooltip appears at wrong position when page is scrolled. On desktop with the current layout, this is unlikely (page likely fits in viewport). On mobile, highly likely.

### BUG-6: renderTimeline called before routeData is loaded (P3)

**Location:** Line 426
**Trigger:** The 1-second interval starts (line 426) and calls `renderTimeline()` before `fetchRoute()` completes. However, line 157 checks `if (!routeData) return` which guards against this. Not a crash, but the interval fires uselessly for the first few seconds.

---

## 6. Redesign Proposal

### Layout Improvements

**A. Responsive grid system (3 breakpoints)**

```
Desktop (>1024px):  [Timeline ─────────────] [Latency ─────────]
                    [Status] [Phase] [Next] [Session] [Quality]

Tablet (768-1024px): [Timeline ─────────────────────────────────]
                     [Latency ──────────────────────────────────]
                     [Status] [Phase]    [Next] [Session]

Mobile (<768px):     [Flight Header ─────]
                     [Quality Score ─────]
                     [Timeline ──────────]
                     [Status] [Phase]
                     [Next]   [Session]
                     [Latency ──────────]
                     [Drop Log ──────────]
```

**B. Header redesign for mobile**

Current header is 2-part (left + right). On mobile, it wraps awkwardly. Proposed:
- Stack: Flight code + route on one line, rating badge + elapsed on second line
- Move refresh indicator to a floating dot in the top-right corner
- Add a connection quality bar (green/yellow/red gradient strip) below the header

**C. Add a real-time quality score card**

Replace the "Session Stats" card with a "Connection Quality" card showing:
- Composite score (0-100) computed from recent ping + HTTP latency + drop frequency
- Sparkline of last 20 quality scores
- Trend arrow (improving/stable/degrading)

### New Components

1. **Quality Score Ring** — A circular gauge (SVG arc) showing 0-100 connection quality. Central number, colored by threshold. This becomes the hero metric of the dashboard.

2. **Route Map Mini** — A simplified SVG of the flight path (just origin/destination dots with a curved line between them and a "you are here" marker). No map tiles needed — just abstract line art on a dark background.

3. **Alert Toast System** — Non-intrusive toasts that appear at the top of the screen:
   - "Entering weak zone in ~30 minutes"
   - "Connection restored after 45s drop"
   - "API latency elevated — checkpoint recommended"

4. **Measurement Sparklines** — Tiny inline charts in each status card showing last 10 data points for that metric.

### Better Data Visualization

- **Latency chart: filter sentinel values** — Skip `-1` measurements instead of plotting them. Show gaps in the line for offline periods.
- **Latency chart: add threshold lines** — Horizontal dashed lines at 1000ms, 3000ms, 5000ms showing "good / acceptable / bad" thresholds.
- **Timeline chart: interpolate current signal** — Instead of showing the "NOW" marker on the x-axis only, interpolate the signal value at the current time and show it as a numeric label (e.g., "NOW: ~42%").
- **Drop log: add duration visualization** — A small bar showing drop duration relative to longest drop in the session.

### Improved Mobile Experience

- Touch targets: Increase waypoint dot tap area to 44x44px using invisible hit areas (`<circle r="22" fill="transparent" stroke="none">` behind each visible dot)
- Swipe navigation: Allow swiping between dashboard sections on mobile
- Chart labels: Increase font size in SVG to minimum 11px rendered (scale SVG text based on viewport width)
- Bottom navigation bar: Quick links to scroll to Timeline, Status, Latency, Drops sections

### Accessibility Improvements

- Add `role="img"` and `aria-label` to both SVG charts describing what they show
- Add `aria-live="polite"` to the stale banner and status card values so screen readers announce changes
- Add `role="status"` to the elapsed timer
- Increase all label text (`--dim` colored) to minimum 12px and ensure 4.5:1 contrast
- Add `:focus-visible` outlines to any interactive elements
- Add `<title>` elements to SVG chart for screen reader summary

### Performance Optimizations

1. **Separate the NOW marker** — Render the static timeline once (on route data change) and overlay the NOW marker as a separate positioned `<div>` or second SVG layer that updates every second. This eliminates 99% of SVG re-rendering.

2. **Use requestAnimationFrame** — Replace `setInterval(() => { updateElapsed(); checkStale(); renderTimeline(); }, 1000)` with `requestAnimationFrame` loop that only runs when the tab is visible. Currently, the intervals fire even when the tab is backgrounded, wasting CPU.

3. **Inline the font** — Base64-encode JetBrains Mono (woff2, ~40KB for 400+700 weights) into the CSS. This eliminates the external font dependency entirely, making the dashboard work even when WiFi is completely down.

4. **Debounce fetch errors** — If fetch fails, exponentially back off (10s, 20s, 40s) instead of retrying every 10 seconds at full rate. On a dead connection, 6 failed fetches per minute is wasteful.

---

## 7. Priority Matrix

| ID | Finding | Priority | Effort | Category |
|----|---------|----------|--------|----------|
| BUG-1 | Empty waypoints crashes updateStatusCards | **P0** | S | Bug |
| BUG-2 | null takeoff_time shows absurd elapsed time | **P0** | S | Bug |
| BUG-3 | Negative latency values render below chart | **P1** | S | Bug |
| PERF-1 | renderTimeline called every 1s, rebuilds entire SVG + re-attaches listeners | **P1** | M | Performance |
| FUNC-1 | fetchRoute only called once — never re-fetched if initially empty | **P1** | S | Functionality |
| ERR-1 | Empty catch blocks in fetch — swallows JSON parse errors, no retry logic | **P1** | S | Code Quality |
| ERR-2 | routeData = {} (truthy) but .waypoints is undefined — crashes renderTimeline on `wp.length` | **P1** | S | Bug |
| FUNC-2 | Session Stats card shows Claude-internal data, not connectivity metrics | **P1** | M | Design |
| A11Y-1 | `--dim` (#475569) on `--card` (#0f172a) is ~3.4:1 contrast — fails WCAG AA | **P2** | S | Accessibility |
| BUG-5 | Tooltip positioning ignores scroll offset | **P2** | S | Bug |
| FONT-1 | JetBrains Mono loaded over network — may fail on bad WiFi, no fallback strategy | **P2** | M | Reliability |
| LAYOUT-1 | No responsive breakpoints below 768px or above 1024px | **P2** | M | Responsive |
| LAYOUT-2 | Charts are always single-column even on wide screens | **P2** | S | Layout |
| FUNC-3 | Latency chart has no tooltips — cannot inspect individual measurements | **P2** | M | Functionality |
| FUNC-4 | egress_city/country always empty — status sub shows "—" permanently | **P2** | S | Data pipeline |
| BUG-4 | Route string split assumes single dash separator | **P2** | S | Bug |
| DATA-1 | Trend threshold (100ms) is arbitrary for satellite WiFi | **P2** | S | Data accuracy |
| PERF-2 | No requestAnimationFrame — intervals fire when tab is backgrounded | **P2** | S | Performance |
| INIT-1 | fetchRoute and fetchLive run sequentially instead of parallel | **P2** | S | Performance |
| A11Y-2 | No ARIA roles, labels, or live regions on any element | **P2** | M | Accessibility |
| FEAT-1 | No connection quality composite score | **P2** | M | Feature |
| FEAT-2 | No alert/notification system for weak zone approach | **P2** | M | Feature |
| A11Y-3 | Stale banner red text is marginal contrast (4.7:1 at 12px) | **P3** | S | Accessibility |
| FONT-2 | Missing crossorigin on preconnect, no preconnect for gstatic | **P3** | S | Performance |
| FONT-3 | Monospace for all text including prose — could use sans-serif for labels | **P3** | S | Typography |
| CSS-1 | No CSS containment on chart cards | **P3** | S | Performance |
| CSS-2 | Minified CSS in style block is hard to maintain | **P3** | S | Maintainability |
| FUNC-5 | No pagination/scroll constraint on drop log | **P3** | S | Functionality |
| FUNC-6 | Drop log peak_latency_ms threshold is hardcoded at 5000ms | **P3** | S | Configuration |
| CODE-1 | setInterval handles not stored — no cleanup path | **P3** | S | Code Quality |
| CODE-2 | No JSDoc or type documentation for data shapes | **P3** | M | Maintainability |
| FEAT-3 | No export/share capability | **P3** | M | Feature |
| FEAT-4 | No route map visualization | **P3** | L | Feature |
| BUG-6 | Interval fires renderTimeline before routeData loads (guarded, no crash) | **P3** | S | Bug |
| LAYOUT-3 | No max-width — content stretches on ultrawide screens | **P3** | S | Layout |

### Summary

- **P0 (fix immediately):** 2 items — both are data edge cases that crash or produce nonsense output
- **P1 (fix before next release):** 6 items — performance, reliability, and data accuracy issues
- **P2 (fix soon):** 15 items — accessibility, responsiveness, missing interactions
- **P3 (backlog):** 12 items — nice-to-haves, maintainability improvements

### Recommended Implementation Order

1. **Sprint A (S effort, critical):** Fix BUG-1, BUG-2, BUG-3, ERR-2 — guard all data access against null/empty/negative values
2. **Sprint B (S-M effort, high value):** Fix PERF-1 (separate NOW marker), FUNC-1 (re-fetch route), ERR-1 (error handling), FONT-1 (inline font)
3. **Sprint C (M effort, UX):** A11Y-1 (contrast), LAYOUT-1+2 (responsive), FUNC-3 (latency tooltips), FUNC-2 (session stats redesign)
4. **Sprint D (M-L effort, features):** FEAT-1 (quality score), FEAT-2 (alerts), A11Y-2 (ARIA), route map

---

*Audit performed on `templates/dashboard.html` at commit `a77d279` (main branch). All line references are to this version of the file.*
