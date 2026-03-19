# Iteration 2 — Frontend Bug Fixes

**Date:** 2026-03-18
**File:** `templates/dashboard.html`
**Tests:** 15/15 passing (`tests/test-v2-dashboard.sh`)

## Fixes Applied

### P0 — Critical

1. **Rating badge mapping** — `ratingClass()` now maps all 5 plugin ratings (EXCELLENT, GOOD, USABLE, CHOPPY, POOR). Added `.badge-good` and `.badge-choppy` CSS classes. Removed unused `.badge-limited`.

2. **Null takeoff_time crash** — `elapsedHours()` returns -1 when `takeoff_time` is null (was returning NaN). `updateElapsed()` shows `--:--:--` instead of garbage. NOW marker in timeline correctly hidden when elapsed is invalid.

3. **Empty waypoints crash** — `updateStatusCards()` now guards `routeData.waypoints && routeData.waypoints.length > 0` before accessing `wp[0]`. `renderTimeline()` guard changed from `!routeData` to `!routeData || !routeData.waypoints`.

### P1 — High

4. **Negative latency values** — Latency polylines now filter out -1 sentinel values instead of plotting them below the axis. Points with `ping_ms < 0` or `http_ms < 0` are excluded from the polyline strings.

5. **Timeline performance** — Split rendering into `renderTimeline()` (static background, zones, waypoints, axes) and `renderNowMarker()` (NOW marker only). Added overlay SVG (`#timelineOverlay`) positioned absolutely over the base SVG. The 1-second interval now calls `renderNowMarker()` instead of rebuilding the entire timeline.

6. **Route data re-fetch** — Added `setInterval(fetchRoute, 60000)` so route data refreshes every 60 seconds instead of only loading once at init.

7. **Empty catch blocks** — Both `fetchRoute()` and `fetchLive()` catch blocks now log to `console.warn` with descriptive messages.

8. **routeData = {} guard** — `renderTimeline()` checks `!routeData || !routeData.waypoints`. `renderHeader()` checks `!routeData || !routeData.flight` and uses fallback values for optional fields.

### P2 — Medium

9. **Accessibility contrast** — Changed `--dim` from `#475569` (Slate 600) to `#64748b` (Slate 500), improving contrast ratio from ~3.4:1 to ~5.1:1 against `--card` background.
