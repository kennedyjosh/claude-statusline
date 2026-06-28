#!/usr/bin/env bash
input=$(cat)

# Parse all fields from input JSON in a single jq call
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "unknown")",
  @sh "cwd=\(.workspace.current_dir // .cwd // "?")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "total=\(.context_window.context_window_size // "")",
  @sh "cost=\(.cost.total_cost_usd // "")",
  @sh "effort=\(.effort.level // "")",
  @sh "thinking=\(.thinking.enabled // "false")",
  @sh "rl5h_pct=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "rl5h_resets=\(.rate_limits.five_hour.resets_at // "")",
  @sh "rl7d_pct=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "rl7d_resets=\(.rate_limits.seven_day.resets_at // "")"
')"

ESC=$'\033'
RESET="${ESC}[0m"

# Git branch with status color
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

# Effort display — prefix ~ when extended thinking is active
effort_display=""
if [ -n "$effort" ]; then
  [ "$thinking" = "true" ] && effort_display="~${effort}" || effort_display="$effort"
fi

# Plan usage from rate_limits (Pro/Max only — absent otherwise)
usage_line=""
if [ -n "$rl5h_pct" ] || [ -n "$rl7d_pct" ]; then
  now=$(date +%s)

  fmt_timer() {
    local secs=$(( $1 < 0 ? 0 : $1 ))
    local days=$(( secs / 86400 ))
    local hours=$(( (secs % 86400) / 3600 ))
    local mins=$(( (secs % 3600) / 60 ))
    if [ "$days" -gt 0 ]; then
      printf "%dd%02dh" "$days" "$hours"
    elif [ "$hours" -gt 0 ]; then
      printf "%dh%02dm" "$hours" "$mins"
    else
      printf "%dm" "$mins"
    fi
  }

  parts=()
  if [ -n "$rl5h_pct" ] && [ -n "$rl5h_resets" ]; then
    pct=$(awk "BEGIN { printf \"%d\", $rl5h_pct + 0 }")
    timer=$(fmt_timer $(( rl5h_resets - now )))
    parts+=("${pct}% resets ${timer}")
  fi
  if [ -n "$rl7d_pct" ] && [ -n "$rl7d_resets" ]; then
    pct=$(awk "BEGIN { printf \"%d\", $rl7d_pct + 0 }")
    timer=$(fmt_timer $(( rl7d_resets - now )))
    parts+=("${pct}% resets ${timer}")
  fi

  if [ ${#parts[@]} -gt 0 ]; then
    IFS=' · '
    usage_line="${parts[*]}"
    unset IFS
  fi
fi

printf "\033[1;34m%s\033[0m \033[3;90m%s\033[0m \033[38;5;28m%s\033[0m%s %s %s" \
  "$model" "$effort_display" "$cwd" "$branch_part" "$context_part" "$cost_part"
if [ -n "$usage_line" ]; then
  printf "\n%s" "$usage_line"
fi
