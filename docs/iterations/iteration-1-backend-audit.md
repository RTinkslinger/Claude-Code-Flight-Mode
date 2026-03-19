# Backend Audit — Iteration 1

**Date:** 2026-03-18
**Scope:** All 12 bash scripts, 3 skill files, hooks.json, 7 data files
**Tests passing at time of audit:** 173

---

## Summary

The codebase is well-structured with consistent patterns (stdin JSON input, python3 for complex logic, `set -uo pipefail`). The main risks cluster around: (1) `set -euo pipefail` in the PostToolUse hook causing silent failures, (2) inconsistent hash length between md5/md5sum fallback paths creating potential dashboard/monitor desync, (3) command injection vectors in variable interpolation into JSON strings, (4) ping flag portability between macOS and Linux, and (5) the flight-off squash logic being fundamentally broken for interleaved commit histories.

---

## CRITICAL

**[SEVERITY: CRITICAL]** Script: `scripts/context-monitor.sh` Line: 5
Description: Uses `set -euo pipefail` (with `-e`) unlike all other scripts which use `set -uo pipefail`. Because this is a PostToolUse hook that runs on **every** tool call (Read, Edit, Write, Bash, Grep, Glob), any command returning non-zero will cause the entire script to exit silently. The jq/awk/curl commands in the latency measurement block (lines 89-181) are particularly vulnerable — if any jq parse fails or curl times out in a way that returns non-zero before `|| true`, the script dies and returns no output to Claude.
Impact: Context tracking silently stops working mid-session. User gets no context budget warnings. Could also cause Claude Code to see unexpected exit codes from the hook.
Fix: Change line 5 from `set -euo pipefail` to `set -uo pipefail` to match all other scripts. The individual `|| true` guards already handle expected failures.

---

**[SEVERITY: CRITICAL]** Script: `skills/flight-off/SKILL.md` Lines: 70-76
Description: The squash logic `git log --oneline | grep -v "flight:" | head -1 | cut -d' ' -f1` is fundamentally wrong. It finds the first non-flight commit in chronological (most recent first) order — not the commit *before the first flight commit*. If the commit history is: `flight:C`, `flight:B`, `non-flight-X`, `flight:A`, `non-flight-base`, this command returns `non-flight-X` (the most recent non-flight commit), and `git reset --soft` to that point would lose `flight:A`'s changes and also reset `non-flight-X`.
Impact: Data loss. Any non-flight commits interleaved with flight commits would be silently re-staged and merged into the squash commit. If there are no non-flight commits in history, `grep -v` returns nothing, and the reset target becomes empty/invalid.
Fix: Walk the log from oldest to newest to find the parent of the first `flight:` commit:
```bash
FIRST_FLIGHT=$(git log --oneline --reverse | grep "flight:" | head -1 | cut -d' ' -f1)
BEFORE_FLIGHT=$(git rev-parse "${FIRST_FLIGHT}^")
```

---

**[SEVERITY: CRITICAL]** Script: `scripts/flight-on-preflight.sh` Lines: 17, 22, 27, 32, 57
Description: Variable values are interpolated directly into JSON strings using shell string concatenation: `echo "{\"input\": \"$FLIGHT_ARGS\", ...}"`. If `FLIGHT_ARGS` contains a double quote, backslash, or newline (e.g., a user types `United "Starlink"`), the generated JSON becomes invalid and python3/jq parsing fails silently. All sub-script calls in lines 17-58 have this issue.
Impact: Invalid JSON fed to sub-scripts, causing them to fail to `|| FALLBACK` paths. The user sees "confidence: none" even with valid input containing special characters.
Fix: Use `jq -n` for JSON construction: `echo "$FLIGHT_ARGS" | jq -Rn --arg pd "$PLUGIN_DIR" '{input: input, plugin_dir: $pd}'` or pass values via environment variables to python3 (which some later scripts already do correctly).

---

## HIGH

**[SEVERITY: HIGH]** Script: `scripts/context-monitor.sh` Lines: 18-24 vs `scripts/dashboard-server.sh` Lines: 25-31
Description: The md5/md5sum fallback produces **different hash lengths**: `md5` (macOS) produces a full 32-character hash, while `md5sum` (Linux) is truncated to 12 characters via `cut -c1-12`. The `cksum` fallback produces a completely different numeric format. Both context-monitor.sh and dashboard-server.sh use this hash to construct `/tmp/flight-mode-*` directory paths. If a session starts on one platform and is somehow resumed or if both commands hit different code paths, the directory names won't match.
Impact: On Linux: the dashboard directory is keyed differently than the context monitor state directory. The live-data.json writes in context-monitor.sh (line 162: `DASHBOARD_DIR="/tmp/flight-mode-dashboard-${DIR_HASH}"`) would target a directory with a 12-char hash, but dashboard-server.sh would have created a directory with a 12-char hash too — so this is actually consistent on Linux. BUT on macOS: md5 produces 32 chars, md5sum is not available, so both use 32 chars — also consistent. The real risk is the cksum fallback (line 30 in dashboard-server.sh) producing an entirely different format (a decimal number, not hex). If md5 is missing on a system where md5sum is also missing, the hash format diverges from expectations.
Fix: Standardize all hash computation. Truncate md5 output to 12 characters everywhere for consistency: `DIR_HASH=$(echo -n "$WORKDIR" | md5 | cut -c1-12)`.

---

**[SEVERITY: HIGH]** Script: `scripts/flight-check.sh` Lines: 189, 194
Description: `ping -c 3 -W 5 8.8.8.8` — on macOS, `-W` takes milliseconds (so `-W 5` = 5ms timeout, far too short to get any reply). On Linux, `-W` takes seconds. The script uses the macOS `ping -c 3 -W 5` expecting a 5-second timeout, but on macOS this is actually a 5-millisecond wait, meaning the ping will almost always report 100% packet loss unless the reply is sub-5ms.
Impact: On macOS, ping-based latency measurement always fails, `ping_avg_ms` stays 0. This doesn't affect the verdict (it mainly relies on curl), but the `ping_avg_ms` metric in the output is always meaningless.
Fix: Use `-W 5000` on macOS or detect the platform: `if [[ "$(uname)" == "Darwin" ]]; then PING_WAIT=5000; else PING_WAIT=5; fi`.

---

**[SEVERITY: HIGH]** Script: `scripts/context-monitor.sh` Lines: 96-97
Description: Same ping portability issue. `ping -c 1 -W 2 8.8.8.8` — on macOS `-W 2` means 2 milliseconds, guaranteeing failure. This runs every 3rd tool call.
Impact: On macOS, `PING_MS` is always -1, leading to false "OFFLINE" detection or skewed API status in live-data.json. The drop detection at line 128-133 also uses PING_MS, so false drops may be recorded.
Fix: Same platform-aware timeout as above.

---

**[SEVERITY: HIGH]** Script: `scripts/context-monitor.sh` Lines: 89-181
Description: The latency measurement block runs on every 3rd PostToolUse hook invocation. It performs: (1) `ping -c 1` (up to 2s timeout), (2) `curl --max-time 3` to api.anthropic.com, (3) multiple jq operations. Total worst-case: ~5 seconds of blocking. The hooks.json timeout for this hook is **5 seconds** (line 34). If both network calls hit their timeouts, the script will be killed by Claude Code before completing, potentially leaving the state file in a corrupted state (line 158-159 writes are non-atomic).
Impact: On every 3rd tool call during degraded connectivity (the exact scenario this tool is designed for), the hook may time out. The state file could be truncated mid-write if the process is killed between echo and file completion.
Fix: (1) Write state file atomically: write to a temp file first, then `mv`. (2) Consider increasing the hook timeout to 8-10 seconds, or reducing `curl --max-time` to 2 seconds. (3) Run ping and curl in parallel with `&` and `wait`.

---

**[SEVERITY: HIGH]** Script: `scripts/dashboard-server.sh` Line: 74
Description: `cd "$SERVE_DIR"` changes the working directory permanently for the rest of the script. If `cmd_start` fails after this point and the script falls through, subsequent operations have an unexpected cwd. More importantly, this `cd` could fail if `$SERVE_DIR` was just created (line 58) but somehow doesn't exist (e.g., /tmp was cleaned). With `set -uo pipefail`, a `cd` failure would not be caught (no `-e` flag), but the `python3 -m http.server` would start in whatever directory the script happened to be in.
Impact: Low probability, but the HTTP server could serve from the wrong directory. The `cd` is also unnecessary because `python3 -m http.server --directory "$SERVE_DIR"` would be more explicit.
Fix: Use `python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVE_DIR"` instead of `cd` + `python3 -m http.server`. Note: `--directory` requires Python 3.7+.

---

**[SEVERITY: HIGH]** Script: `scripts/flight-on-activate.sh` Lines: 90-96
Description: The output JSON (lines 90-96) interpolates `$CWD` directly into a JSON string without escaping. If the user's working directory path contains a double quote or backslash (e.g., `/home/user/"project"`), the JSON output becomes invalid.
Impact: The calling script (preflight or skill) receives malformed JSON and may fail to parse the activation result.
Fix: Use `jq -n` to construct the output JSON: `jq -n --arg fm "$CWD/FLIGHT_MODE.md" --arg fs "$CWD/.flight-state.md" '{status:"activated", flight_mode_path:$fm, flight_state_path:$fs}'`.

---

## MEDIUM

**[SEVERITY: MEDIUM]** Script: `scripts/flight-on-lookup.sh` Line: 7
Description: `INPUT=$(cat)` reads all of stdin without a timeout or size limit. If called without stdin being piped (e.g., accidentally invoked from a terminal), it blocks indefinitely waiting for input. Other scripts (parse-flight.sh, network-detect.sh, flight-check.sh) all check `[ -t 0 ]` first to avoid blocking on a TTY.
Impact: If a user manually runs `bash scripts/flight-on-lookup.sh`, the terminal hangs. Not a production issue since it's always called via pipe from preflight.sh.
Fix: Add TTY check: `if [ -t 0 ]; then echo '{"error":"no stdin"}'; exit 1; fi` before `INPUT=$(cat)`.

---

**[SEVERITY: MEDIUM]** Script: `scripts/flight-on-lookup.sh` Lines: 48-52
Description: `os.environ["PROFILES_VAR"]` uses direct dictionary access (not `.get()`). If the environment variable is somehow not set, this throws a `KeyError` and the entire python3 block fails with no output. Lines 49-52 have the same pattern for AIRLINES_VAR, CORRIDORS_VAR, AIRPORTS_VAR, EGRESS_VAR.
Impact: If any of the environment variables are truncated or not passed (e.g., if the variable value is too long for the environment), the script fails silently.
Fix: Use `os.environ.get("PROFILES_VAR", "")` and handle empty path in `load()`.

---

**[SEVERITY: MEDIUM]** Script: `scripts/stop-checkpoint.sh` Line: 35
Description: Uses `--no-verify` to skip pre-commit hooks. While the comment (line 5) explains the rationale, this bypasses all hooks including potential secret-scanning hooks. If the user has a secrets detection pre-commit hook, `--no-verify` could commit sensitive data.
Impact: Potential secrets committed to git during an auto-checkpoint. The rationale (emergency save on shaky WiFi) is valid, but the user should be aware.
Fix: This is a design tradeoff, not a bug. Consider making `--no-verify` configurable via an environment variable or a setting in FLIGHT_MODE.md.

---

**[SEVERITY: MEDIUM]** Script: `scripts/stop-checkpoint.sh` Lines: 19-21
Description: The infinite loop guard checks `stop_hook_active` from hook input JSON. However, the hook framework may not actually set this field. If the Stop hook fires multiple times (e.g., multiple simultaneous sessions ending), there's no file-based lock to prevent concurrent commits.
Impact: Two concurrent sessions ending simultaneously could race on `git add -u` and `git commit`, potentially creating duplicate commits or merge conflicts.
Fix: Use a lock file: `LOCK=/tmp/flight-mode-stop-lock; if ! mkdir "$LOCK" 2>/dev/null; then exit 0; fi; trap "rmdir $LOCK" EXIT`.

---

**[SEVERITY: MEDIUM]** Script: `scripts/context-monitor.sh` Lines: 57-59
Description: The state file write is not atomic. `cat > "$STATE_FILE"` truncates the file before writing. If the process is killed (e.g., hook timeout) between truncation and write completion, the state file becomes empty, resetting all counters to 0.
Impact: Context tracking counters reset to 0, causing the user to miss context budget warnings for the remainder of the session. The latency measurement block (line 155-159) has the same issue with `echo "$UPDATED_STATE" > "$STATE_FILE"`.
Fix: Write to a temp file and rename: `cat > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"`.

---

**[SEVERITY: MEDIUM]** Script: `scripts/flight-check.sh` Line: 119
Description: `api_latency_ms=$(python3 -c "print(int(float('$time_total') * 1000))")` — the variable `$time_total` is interpolated into a python3 command string. If curl returns unexpected output (e.g., an error message instead of a number), this becomes a code injection vector. For example, if `time_total` were `__import__('os').system('rm -rf /')`, it would execute.
Impact: Very low probability (curl's `-w` format string is deterministic), but violates defense-in-depth. The same pattern appears at lines 194 and 206 with `$ping_avg` and `$dl_output`.
Fix: Pass via environment variable: `TIME_VAR="$time_total" python3 -c "import os; print(int(float(os.environ.get('TIME_VAR','0')) * 1000))"`.

---

**[SEVERITY: MEDIUM]** Script: `scripts/measure-latency.sh` Lines: 17-24
Description: The ping result is checked using `$?` on line 18, but `$?` refers to the last command in the pipeline. Since `PING_OUTPUT=$(ping ...)` captures the output, `$?` is correct here. However, on line 17, the `PING_OUTPUT` is set even on failure, so the `else` branch on line 21-23 may never fire if `ping` produces partial output before timing out on macOS.
Impact: Minor — the latency output may contain partial/garbage values.
Fix: Check the output content rather than just the exit code: verify `PING_AVG` is a valid number.

---

**[SEVERITY: MEDIUM]** Script: `scripts/measure-latency.sh` Line: 33
Description: `dig` may not be installed on all systems (it's part of `bind-tools` or `dnsutils`). There's no fallback.
Impact: DNS timing metric always shows "timeout" on systems without dig installed. Not a critical measurement though.
Fix: Add fallback: `command -v dig >/dev/null 2>&1 && DNS_TIME=$(dig ...) || DNS_TIME="unavailable"`.

---

**[SEVERITY: MEDIUM]** Script: `scripts/measure-latency.sh` Line: 45
Description: `NOTES="${1:-}"` captures `$1` as notes, but `$1` was already consumed on line 9 for the `--header` check. If the user runs `measure-latency.sh "some note"`, that note is captured. But if run `measure-latency.sh --header`, line 9 exits before reaching line 45. If run `measure-latency.sh`, `$1` is empty. This is correct but potentially confusing — the notes feature is undocumented beyond the comment on line 44.
Impact: None functionally, but the usage comment at line 4 doesn't mention the notes parameter.
Fix: Document the notes parameter in the usage comment.

---

**[SEVERITY: MEDIUM]** Script: `scripts/network-detect.sh` Lines: 96-131
Description: The Python code opens the SSID file with `with open(ssids_file) as f` without error handling for file read failures. If the file exists but is corrupt (e.g., invalid JSON), the script crashes and `match` variable on line 96 is empty, handled by the `|| true` on line 131. However, the error message is swallowed — the user gets "type: other" with no indication that the pattern file was corrupt.
Impact: Silent failure when pattern file is damaged.
Fix: This is acceptable given the fallback, but consider logging to stderr for debugging.

---

**[SEVERITY: MEDIUM]** Script: `scripts/network-detect.sh` Lines: 112-114
Description: The confidence check `if pattern.lower() == ssid.lower()` compares a regex pattern string to the SSID literally. A pattern like `gogoinflight` (which is a literal string that happens to also be a valid regex) matches correctly. But if patterns contained actual regex metacharacters (e.g., `Free.*WiFi`), comparing `pattern.lower() == ssid.lower()` would never match even for an exact SSID hit. Currently, the airline_patterns don't use regex metacharacters, but the airport_patterns do (line 36 of wifi-ssids.json: `"Free.*WiFi"`).
Impact: The confidence logic is applied only to airline_patterns (line 106), not airport_patterns (line 122), so this doesn't cause incorrect behavior today. But if airline patterns add regex metacharacters in the future, confidence detection breaks.
Fix: Document that airline_patterns should use literal strings. Or compare against the match group rather than the pattern.

---

**[SEVERITY: MEDIUM]** Script: `scripts/block-direct-flight-mode.sh` Line: 7
Description: `grep -qF "FLIGHT_MODE.md"` uses a fixed-string match on the full file_path. This blocks writes to ANY file whose path contains "FLIGHT_MODE.md" as a substring, including paths like `/some/other/FLIGHT_MODE.md.bak` or `/project/docs/about-FLIGHT_MODE.md`. The `-F` flag means no regex, but the substring match is overly broad.
Impact: False positives blocking writes to unrelated files that happen to contain "FLIGHT_MODE.md" in their path. Low probability but annoying if it happens.
Fix: Match the basename: `if [ "$(basename "$FILE_PATH")" = "FLIGHT_MODE.md" ]; then`.

---

**[SEVERITY: MEDIUM]** Data: `data/supported-countries.json` Line: 29
Description: Hong Kong (HK) is listed as "explicitly excluded" with note "explicitly excluded from both API and Claude.ai access". Meanwhile, `data/airport-codes.json` has HKG with country "HK" and `data/airline-codes.json` has CX (Cathay Pacific) with country "HK". Users flying Cathay Pacific departing HKG will see API status "BLOCKED" due to HKG being in an excluded country — but Cathay's WiFi (Gogo provider) egresses through US ground stations, so the API should actually work. The flight-check correctly tests actual reachability, but the egress_country check against supported-countries.json could show a misleading warning if the geo-IP lookup returns HK before the satellite routing kicks in.
Impact: Potentially misleading warning for CX flights, though the actual API reachability test would show GO/CAUTION.
Fix: The provider-egress.json already documents that Gogo egresses via US. Consider suppressing the country warning when the provider's `api_safe` is `true` and the egress country matches one of the provider's known egress countries.

---

## LOW

**[SEVERITY: LOW]** Script: `scripts/flight-on-preflight.sh` Line: 73
Description: `except: return None` — bare except clause catches all exceptions including SystemExit and KeyboardInterrupt. Should use `except Exception`.
Impact: Very minor — the function `p()` is a JSON parser helper. If `json.loads()` raises anything unusual, it's correctly treated as "not valid JSON". But bare except is a Python anti-pattern.
Fix: Change to `except Exception: return None`.

---

**[SEVERITY: LOW]** Script: `scripts/parse-flight.sh` Lines: 60-67
Description: The `emit_result` function uses local variable names that shadow common bash builtins/variables (`ac`, `an`, `og`, `ds`). While not technically a problem, the single-line conditional assignments (e.g., `local ac; [ "$airline_code" = "null" ] && ac="null" || ac="\"$airline_code\""`) use the `cmd1 && cmd2 || cmd3` anti-pattern. If `ac="null"` fails (which it can't for variable assignment, but in general this pattern is fragile), `cmd3` would also execute.
Impact: None in practice for variable assignments. Style concern only.
Fix: Use proper if/else for clarity, or accept the pattern since variable assignment never fails.

---

**[SEVERITY: LOW]** Script: `scripts/parse-flight.sh` Line: 78
Description: `"parsed_from": "$parsed_from"` always quotes `parsed_from` (line 78) even though the emit_result function also handles null for this field on line 67 (`local pf; ...`). But the heredoc on line 78 uses `"$parsed_from"` directly (always quoted), while line 67 sets `pf` (unquoted when null) — and `pf` is never used in the heredoc. This means `parsed_from` is always output as a string, never as JSON null, which is inconsistent with other fields.
Impact: The JSON output has `"parsed_from": "null"` (string "null") instead of `"parsed_from": null` (JSON null) when the value is null. The Python code path (line 190) uses proper JSON serialization so this only affects the bash fallback path (line 358).
Fix: Use `$pf` instead of `"$parsed_from"` on line 78 of the heredoc.

---

**[SEVERITY: LOW]** Script: `scripts/dashboard-server.sh` Line: 66
Description: When the dashboard template doesn't exist, the placeholder HTML includes the raw `$dashboard_src` path, potentially leaking internal file paths to anyone who opens the dashboard.
Impact: Information disclosure of plugin installation path. Only accessible on localhost:8234.
Fix: Use a generic message: `"Dashboard template not yet installed."`.

---

**[SEVERITY: LOW]** Script: `scripts/dashboard-server.sh` Lines: 93-98
Description: The graceful shutdown loop sleeps 0.1s * 10 iterations = 1 second, then force-kills. The `sleep 0.1` may not be supported on all platforms (some older busybox implementations only support integer sleep).
Impact: Unlikely on macOS/modern Linux. Only affects embedded/minimal systems.
Fix: Acceptable for the target platform.

---

**[SEVERITY: LOW]** Script: `scripts/test-monitor.sh` Lines: 84, 106
Description: `md5 -q` is macOS-specific. The fallback `md5sum` path uses `cut -c1-12` which truncates the hash. If the same file is hashed by both paths on different runs (shouldn't happen on a single machine), the hashes won't match and the monitor will report false "updated" events.
Impact: None in practice — a single machine uses one hash utility consistently.
Fix: Acceptable.

---

**[SEVERITY: LOW]** Script: `scripts/network-detect.sh` Lines: 68-74
Description: The `airport -I` command is deprecated on macOS Sonoma+ and may be removed in future macOS versions. The fallback to `networksetup -getairportnetwork en0` assumes WiFi is on `en0`, which may not be true on all Mac configurations (especially USB WiFi adapters or VMs).
Impact: SSID detection could fail on newer macOS versions or non-standard network configurations. The fallback chain handles this gracefully (returns "type: none").
Fix: Consider using `system_profiler SPAirPortDataType` as an additional fallback, or the newer `wdutil info` command (macOS Sonoma+).

---

**[SEVERITY: LOW]** Script: `scripts/context-monitor.sh` Lines: 66-69
Description: The context usage estimation formula `(tool_calls * 2.5 + lines_read * 0.01) / 1.5` is a rough heuristic. There's no calibration or validation that this actually correlates with real context window usage. The comment on line 63 says "maps to ~100% at typical session limits" but provides no data.
Impact: Users might get 45% warnings very early or 85% warnings too late, depending on the nature of their work (lots of small tool calls vs. few large file reads).
Fix: This is a known approximation. Consider logging actual context usage (if Claude Code exposes it) and calibrating the formula. Document the known inaccuracy in a code comment.

---

**[SEVERITY: LOW]** Script: `scripts/flight-on-activate.sh` Lines: 41-63, 65-88
Description: FLIGHT_MODE.md and .flight-state.md are written using heredocs with unquoted delimiters (`<< FMEOF` and `<< FSEOF`). This means shell variable expansion is active inside the heredoc. If any of the variables (`$AIRLINE_NAME`, `$PROVIDER`, etc.) contain backticks, dollar signs, or backslash sequences, they would be interpreted by the shell.
Impact: If an airline name or note contained `$HOME` or backticks, the rendered file would have unexpected content. Current data files don't have such values, but future additions could.
Fix: Use quoted heredoc delimiters (`<< 'FMEOF'`) and interpolate variables via sed or envsubst afterward. Alternatively, accept the risk since the data is controlled.

---

**[SEVERITY: LOW]** Data: `data/airline-codes.json`
Description: Missing some notable airlines: F9 (Frontier), NK (Spirit). These have profiles in airline-profiles.json but no entries in airline-codes.json. A user inputting "F9123" or "NK456" would fail to parse via the lookup path in parse-flight.sh because the code won't find the airline code in the codes file.
Impact: Users on Frontier or Spirit flights can't use flight code parsing. They'd need to enter the airline name instead.
Fix: Add missing airline codes: `"F9": {"name": "Frontier Airlines", "provider": "none", "country": "US"}` and `"NK": {"name": "Spirit Airlines", "provider": "ses", "country": "US"}`.

---

**[SEVERITY: LOW]** Data: `data/airline-profiles.json` Line: 254
Description: IndiGo note says "No WiFi until late 2025" — it's now March 2026. This is stale.
Impact: Incorrect user-facing information.
Fix: Update to reflect current status (check if IndiGo has WiFi as of 2026).

---

**[SEVERITY: LOW]** Data: `data/route-corridors.json`
Description: No South America corridors (e.g., GRU-MIA, SCL-LAX, GRU-LIS). No Africa corridors (e.g., JNB-LHR, ADD-DXB). Users on these routes get `corridor: "unknown"` with a rough distance-based duration estimate. The haversine-based duration (`dist / 850`) in flight-on-lookup.sh (line 145) assumes 850 km/h which is reasonable for cruise speed but doesn't account for routing overhead.
Impact: Less useful corridor information for Africa and South America routes. Duration estimate may be off by ~10-20%.
Fix: Add corridors for these regions in future iterations. The fallback behavior is acceptable.

---

**[SEVERITY: LOW]** Data: `data/wifi-ssids.json`
Description: Airline SSID patterns use exact/simple strings (good), but the pattern `"Hawaiian"` (line 12) is very broad and could match any WiFi network containing "Hawaiian" (e.g., a coffee shop called "Hawaiian Joe's WiFi"). Similarly, `"LATAM"` (line 31) could match non-airline networks.
Impact: False positive airline WiFi detection for broadly-named patterns.
Fix: Use more specific patterns: `"HawaiianAir"` or `"^Hawaiian$"` or `"Hawaiian_WiFi"`. Verify actual SSID strings used by these airlines.

---

**[SEVERITY: LOW]** Script: `hooks/hooks.json` Line: 34
Description: The PostToolUse hook timeout is 5 seconds. Given that context-monitor.sh performs network calls (ping + curl) every 3rd invocation, this timeout is tight. On degraded WiFi (the primary use case), both ping and curl could take 2-3 seconds each.
Impact: As noted in the HIGH severity finding above, the hook may time out during degraded connectivity.
Fix: Increase to 8-10 seconds, or split the latency measurement into its own async process.

---

**[SEVERITY: LOW]** Script: `scripts/flight-on-preflight.sh` Lines: 62-85
Description: The final assembly uses `python3 -c` with `os.environ` to read large JSON strings from environment variables. Environment variable size limits vary by system (typically 128KB-2MB total for all env vars). The `LOOKUP_VAR` from line 66 could be large if the corridor has many waypoints.
Impact: On systems with very low environment variable limits, python3 could fail to receive the full JSON. Unlikely in practice.
Fix: Consider writing intermediate results to temp files instead of environment variables for very large payloads.

---

## Data File Completeness Assessment

### airline-codes.json (67 airlines + _note)
**Coverage:** Good for major carriers worldwide. Covers US Big 4, European majors, ME3, Asian majors, Oceania.
**Missing:** F9 (Frontier), NK (Spirit), G3 (Gol), TP already present but some regional carriers missing.
**Accuracy:** Provider assignments look reasonable based on public data. WN (Southwest) listed as "starlink" is forward-looking (Starlink rollout in progress).

### airport-codes.json (98 airports + _note)
**Coverage:** Good for international hubs. Missing some secondary hubs that are common connection points (e.g., DOH has entry, but some regional airports missing).
**Accuracy:** Lat/lon coordinates spot-checked and appear correct.

### route-corridors.json (9 corridors)
**Coverage:** Major routes covered: transpacific (N+S), transatlantic, polar, Asia-Europe, US domestic, intra-Europe, intra-Asia, ME-Europe, Australia-Asia. Missing: South America routes, Africa routes, India subcontinent routes.
**Accuracy:** Waypoint coordinates follow plausible great-circle routes. Signal strength models are reasonable approximations. Weak zones align with known satellite coverage gaps.

### provider-egress.json (7 providers)
**Coverage:** All major IFC providers represented.
**Accuracy:** Starlink entry notes ISL routing variability — good. ASN numbers provided for traceability. One note: `api_safe: "variable"` for Starlink is a string, while other entries use boolean `true/false`. This type inconsistency could cause issues if code does `== true` comparison.

### supported-countries.json
**Coverage:** Comprehensive list, recently updated (2026-03-10).
**Accuracy:** Exclusions match known Anthropic policy.

### wifi-ssids.json
**Coverage:** 30 airline patterns, 6 airport patterns. Good coverage of major carriers.
**Accuracy:** SSID patterns are reasonable approximations. Some may not match actual in-flight SSIDs exactly.

---

## Cross-Cutting Observations

### Positive Patterns
1. Consistent plugin directory resolution across all scripts (stdin JSON > env var > script location)
2. Good fallback chains for external commands (md5/md5sum/cksum, airport/networksetup)
3. All scripts produce valid JSON output even on failure
4. Python3 used appropriately for complex logic, keeping bash as orchestration layer
5. `set -uo pipefail` (without `-e`) is the correct choice for scripts that handle errors locally — context-monitor.sh is the exception

### Architecture Concerns
1. **No cleanup mechanism for /tmp state files.** State files in `/tmp/flight-mode-*` accumulate over sessions. On long-lived machines, these directories pile up. Consider adding a cleanup step to `/flight-off` or a timestamp-based cleanup in context-monitor.sh.
2. **No mechanism to detect stale flight mode.** If a session crashes without running the Stop hook, `FLIGHT_MODE.md` persists and the next session inherits flight mode behavior even if the user is no longer on a plane. Consider adding a timestamp check in the hooks.
3. **Dashboard server runs indefinitely.** The `python3 -m http.server` process survives session end. `/flight-off` doesn't explicitly stop it. Only `dashboard-server.sh stop` kills it, and the SKILL.md for flight-off doesn't call it.

---

## Priority Remediation Order

1. **CRITICAL:** Fix `set -euo pipefail` in context-monitor.sh (1 character change, highest impact)
2. **CRITICAL:** Fix flight-off squash logic (design-level fix needed)
3. **CRITICAL:** Fix JSON injection in flight-on-preflight.sh (use jq or env vars)
4. **HIGH:** Fix ping `-W` portability (macOS milliseconds vs Linux seconds)
5. **HIGH:** Fix non-atomic state file writes in context-monitor.sh
6. **HIGH:** Increase PostToolUse hook timeout or reduce network call timeouts
7. **MEDIUM:** Add missing airline codes (F9, NK) to airline-codes.json
8. **LOW:** Everything else
