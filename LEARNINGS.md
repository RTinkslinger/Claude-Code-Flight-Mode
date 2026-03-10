# LEARNINGS.md

Trial-and-error patterns discovered during Claude Code sessions.
Patterns confirmed 2+ times graduate to CLAUDE.md during milestone compaction.

## Active Patterns

### 2026-03-10 - Sprint 2
- Tried: Monitoring test with filesystem-only log capture, then asking user to fill in session UX observations
  Works: Log capture should also pipe session output to a file (e.g., `claude ... | tee /tmp/session-log.txt`) or capture terminal output. Only ask user for subjective observations (design gaps, product feel) — never for factual data that could have been captured.
  Context: Phase 3 live skill testing. Filesystem polling captured state changes but missed all Claude chat output (summaries, confirmations, questions). User correctly pointed out this was information I should have captured, not asked about.
  Confirmed: 1x

- Tried: `rm -rf /tmp/flight-mode-dashboard-*` in zsh without null_glob
  Works: `rm -rf /tmp/flight-mode-dashboard-* 2>/dev/null; true` or use `setopt null_glob` — zsh treats unmatched globs as errors by default
  Context: Log capture script startup. Crashed immediately because no dashboard dirs existed yet.
  Confirmed: 1x
