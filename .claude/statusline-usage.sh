#!/usr/bin/env bash
input=$(cat)

color() {
  if   (( $1 >= $3 )); then printf '\033[31m'
  elif (( $1 >= $2 )); then printf '\033[33m'
  else                       printf '\033[32m'
  fi
}
reset=$'\033[0m'

ctx=$(jq -r '.context_window.used_percentage // 0 | floor' <<<"$input")
five=$(jq -r '.rate_limits.five_hour.used_percentage // empty | floor' <<<"$input")
seven=$(jq -r '.rate_limits.seven_day.used_percentage // empty | floor' <<<"$input")
cost=$(jq -r '.cost.total_cost_usd // 0' <<<"$input")
model=$(jq -r '.model.display_name // .model.id // ""' <<<"$input")
effort=$(jq -r '.effort.level // ""' <<<"$input")
cwd=$(jq -r '.workspace.current_dir // ""' <<<"$input")
short_cwd=$(awk -F/ '{print $(NF-1)"/"$NF}' <<<"$cwd")
[[ -n $effort ]] && model_str="$model ($effort)" || model_str="$model"

if [[ -z $five && -z $seven ]]; then
  printf '%s  |  %s  |  \033[36m[API]\033[0m  cost: $%.4f  |  ctx: %s%d%%%s' \
    "$short_cwd" "$model_str" "$cost" "$(color "$ctx" 70 80)" "$ctx" "$reset"
else
  printf '%s  |  %s  |  ctx: %s%d%%%s' \
    "$short_cwd" "$model_str" "$(color "$ctx" 70 80)" "$ctx" "$reset"
fi
