#!/usr/bin/env bash
input=$(cat)

# Parse all fields from input JSON in a single jq call
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "unknown")",
  @sh "cwd=\(.workspace.current_dir // .cwd // "?")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "total=\(.context_window.context_window_size // "")",
  @sh "cost=\(.cost.total_cost_usd // "")",
  @sh "transcript=\(.transcript_path // "")"
')"

# Effort level: parse from transcript JSONL (most recent /model change), fall back to settings.json
effort=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  effort=$(tac "$transcript" | sed -n 's/.*Set model to.* with \(low\|medium\|high\|max\) effort.*/\1/p' | head -1 2>/dev/null)
fi
if [ -z "$effort" ]; then
  config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  effort=$(jq -r '.effortLevel // empty' "$config_dir/settings.json" 2>/dev/null)
fi
[ -z "$effort" ] && effort="medium"

# Git branch with status color
ESC=$'\033'
RESET="${ESC}[0m"
git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
branch_part=""
if [ -n "$git_branch" ]; then
  git_dirty=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" status --porcelain 2>/dev/null)
  git_ahead=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-list "@{u}..HEAD" 2>/dev/null | wc -l | tr -d ' ')
  if [ -n "$git_dirty" ]; then
    branch_color="${ESC}[0;31m"
  elif [ "${git_ahead:-0}" -gt 0 ] 2>/dev/null; then
    branch_color="${ESC}[0;33m"
  else
    branch_color="${ESC}[0;32m"
  fi
  branch_part=" ⎇ ${branch_color}${git_branch}${RESET}"
fi

# Context: "used/max (pct%)"
# used_percentage is null after /clear (no messages sent yet in new session).
# In that case, fall back to 0% used but still show the window size.
if [ -n "$total" ]; then
  used_val="${used:-0}"
  context_part=$(awk "BEGIN {
    used_pct = $used_val + 0
    total = $total + 0
    used_tok = int(used_pct / 100 * total + 0.5)
    if (used_tok >= 1000) printf \"%dk\", used_tok/1000; else printf \"%d\", used_tok
    if (total >= 1000) printf \"/%dk\", total/1000; else printf \"/%d\", total
    printf \" (%d%%)\n\", used_pct
  }")
else
  context_part="no ctx"
fi

# Session cost
cost_part=""
if [ -n "$cost" ]; then
  cost_part=$(awk "BEGIN { printf \"\$%.2f\", $cost + 0 }")
fi

# Plan usage (5-hour and 7-day utilization) via Anthropic OAuth API
usage_line=""
cache_dir="$HOME/.cache/claude-statusline"
cache_file="$cache_dir/usage.json"
rate_limit_file="$cache_dir/rate-limited-until"
cache_ttl=180
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
token=$(jq -r '.claudeAiOauth.accessToken // empty' "$config_dir/.credentials.json" 2>/dev/null)

if [ -n "$token" ]; then
  mkdir -p "$cache_dir"
  now=$(date +%s)
  use_cache=false
  rate_limited=false

  # Check if we're currently rate limited
  if [ -f "$rate_limit_file" ]; then
    rate_limit_until=$(cat "$rate_limit_file" 2>/dev/null)
    if [ "$now" -lt "$rate_limit_until" ] 2>/dev/null; then
      use_cache=true
      rate_limited=true
    else
      rm -f "$rate_limit_file"
    fi
  fi

  if [ "$rate_limited" = false ] && [ -f "$cache_file" ]; then
    cache_age=$(( now - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
    if [ "$cache_age" -lt "$cache_ttl" ]; then
      use_cache=true
    fi
  fi

  if [ "$use_cache" = false ]; then
    headers_file=$(mktemp)
    response=$(curl -s -D "$headers_file" --max-time 5 \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
      tmp_cache=$(mktemp "$cache_dir/usage.XXXXXX")
      echo "$response" > "$tmp_cache" && mv -f "$tmp_cache" "$cache_file"
      rm -f "$rate_limit_file"
    elif echo "$response" | jq -e '.error.type == "rate_limit_error"' >/dev/null 2>&1; then
      retry_after=$(grep -i 'retry-after' "$headers_file" 2>/dev/null | tr -d '\r' | awk '{print $2}')
      [ -z "$retry_after" ] && retry_after=300
      echo $(( now + retry_after )) > "$rate_limit_file"
    fi
    rm -f "$headers_file"
  fi

  if [ -f "$cache_file" ]; then
    usage_line=$(python3 -c "
import json, datetime, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

now = datetime.datetime.now(datetime.timezone.utc)

def fmt_timer(total_secs):
    days, rem = divmod(total_secs, 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    if days > 0:
        return f'{days}d{hours:02d}h'
    elif hours > 0:
        return f'{hours}h{minutes:02d}m'
    else:
        return f'{minutes}m'

parts = []
for key in ['five_hour', 'seven_day']:
    block = data.get(key)
    if not block:
        continue
    pct = block.get('utilization', 0)
    resets_at = block.get('resets_at', '')
    if resets_at:
        reset_dt = datetime.datetime.fromisoformat(resets_at)
        diff = reset_dt - now
        timer = fmt_timer(max(0, int(diff.total_seconds())))
    else:
        timer = '?'
    parts.append(f'{pct:.0f}% resets {timer}')

# Rate limit indicator
rate_limit_msg = ''
try:
    with open(sys.argv[2]) as f:
        until = int(f.read().strip())
    remaining = until - int(now.timestamp())
    if remaining > 0:
        rate_limit_msg = f' | rate-limited for {fmt_timer(remaining)}'
except:
    pass

if parts:
    print(' \u00b7 '.join(parts) + rate_limit_msg)
" "$cache_file" "$rate_limit_file" 2>/dev/null)
  fi
fi

printf "\033[1;34m%s\033[0m \033[3;90m%s\033[0m \033[38;5;28m%s\033[0m%s %s %s" \
  "$model" "$effort" "$cwd" "$branch_part" "$context_part" "$cost_part"
if [ -n "$usage_line" ]; then
  printf "\n%s" "$usage_line"
fi
