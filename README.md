# claude-statusline

A custom status line for [Claude Code](https://claude.ai/code) that displays model, effort level, working directory, git branch status, context window usage, session cost, session ID, and plan usage.

## How it looks

<img src="statusline-preview.svg" alt="statusline preview">

**Line 1:** Model, effort level, working directory, git branch, context window, and session cost. The git branch is color-coded: **green** when clean, **yellow** when ahead of remote, and **red** when there are uncommitted changes.

**Line 2:** Session ID.

**Line 3:** 5-hour and 7-day plan usage with reset countdowns. Only shown if you're on a Claude Pro or Max plan.

## Installation

Add the following to your `.claude/settings.json` (global: `~/.claude/settings.json`, or local: `.claude/settings.json` in your project):

```json
{
  "statusLine": {
    "type": "command",
    "command": "npx -y github:kennedyjosh/claude-statusline"
  }
}
```

## Requirements

- `jq` — for parsing JSON input
- `python3` — for formatting usage data
- `curl` — for fetching plan usage from the API
- `git` — for branch/status info
