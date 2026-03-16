# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-03-16

### Added
- Status line displaying model, effort level, working directory, git branch, context window usage, and session cost
- Git branch color-coding: green (clean), yellow (ahead of remote), red (uncommitted changes)
- Effort level parsing from session transcript JSONL with settings.json fallback
- Session ID on second line
- Plan usage display (5-hour and 7-day utilization with reset countdowns) for Pro/Max plans
- Rate-limit detection with countdown indicator
- Server time-based reset countdowns for accuracy independent of local clock
- Animated SVG preview in README
- Pre-commit hook to auto-update changelog
