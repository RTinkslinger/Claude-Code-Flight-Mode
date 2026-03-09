# CLAUDE.md Snippet for Flight Mode

Add this to your `~/.claude/CLAUDE.md` (global config, one-time setup):

```markdown
## Flight Mode
If `FLIGHT_MODE.md` exists in this repo root, read it before doing anything else.
If `.flight-state.md` exists with incomplete tasks, resume from the last checkpoint.
```

This enables automatic flight mode detection and session recovery across all repos.
