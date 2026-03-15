# claude-statusline

A custom status line for [Claude Code](https://claude.ai/code) that displays model, effort level, working directory, git branch status, context window usage, and session cost.

## How it looks

<img src="statusline-preview.svg" alt="statusline preview">

The git branch is color-coded: **green** when clean, **yellow** when ahead of remote, and **red** when there are uncommitted changes.

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
- `python3` — for formatting numbers
- `git` — for branch/status info
