#!/usr/bin/env bash
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

# Effort level: parse from transcript JSONL (most recent /model change), fall back to settings.json
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
effort=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  effort=$(tac "$transcript" | grep -oP 'Set model to[\s\S]*? with \K(low|medium|high|max)(?= effort)' -m1 2>/dev/null)
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
  context_part=$(python3 -c "
used_pct = float('$used_val')
total = $total
used_tok = round(used_pct / 100 * total)
def fmt(n): return f'{n/1000:.0f}k' if n >= 1000 else str(n)
print(f'{fmt(used_tok)}/{fmt(total)} ({used_pct:.0f}%)')
" 2>/dev/null)
else
  context_part="no ctx"
fi

# Session cost
cost_part=""
if [ -n "$cost" ]; then
  cost_part=$(python3 -c "print('\$' + f'{float(\"$cost\"):.2f}')" 2>/dev/null)
fi

printf "\033[1;34m%s\033[0m \033[3;90m%s\033[0m \033[38;5;28m%s\033[0m%s %s %s" \
  "$model" "$effort" "$cwd" "$branch_part" "$context_part" "$cost_part"
