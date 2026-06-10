#!/usr/bin/env bash
input=$(cat)

bar() {
  local pct=$1 width=8 filled
  filled=$(( pct * width / 100 ))
  (( filled > width )) && filled=$width
  printf '%*s' "$filled" '' | tr ' ' '#'
  printf '%*s' "$((width - filled))" '' | tr ' ' '-'
}

color() {
  if   (( $1 >= $3 )); then printf '\033[31m'
  elif (( $1 >= $2 )); then printf '\033[33m'
  else                       printf '\033[32m'
  fi
}
reset=$'\033[0m'

countdown() {
  local now diff
  now=$(date +%s)
  diff=$(( $1 - now ))
  (( diff <= 0 )) && { printf 'now'; return; }
  if   (( diff >= 86400 )); then printf '%dd %dh' $(( diff/86400 )) $(( (diff%86400)/3600 ))
  elif (( diff >= 3600 ));  then printf '%dh %dm' $(( diff/3600 ))  $(( (diff%3600)/60 ))
  else                           printf '%dm'     $(( diff/60 ))
  fi
}

ctx=$(jq -r '.context_window.used_percentage // 0 | floor' <<<"$input")
five=$(jq -r '.rate_limits.five_hour.used_percentage // empty | floor' <<<"$input")
seven=$(jq -r '.rate_limits.seven_day.used_percentage // empty | floor' <<<"$input")

if [[ -z $five && -z $seven ]]; then
  printf '\033[36m[API]\033[0m  ctx: %s%s%s %d%%' \
    "$(color "$ctx" 70 80)" "$(bar "$ctx")" "$reset" "$ctx"
else
  fr=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")
  sr=$(jq -r '.rate_limits.seven_day.resets_at // empty' <<<"$input")
  printf '5h: %s%s%s %d%% (%s)  |  7d: %s%s%s %d%% (%s)  |  ctx: %s%s%s %d%%' \
    "$(color "$five" 80 90)"  "$(bar "$five")"  "$reset" "$five"  "$(countdown "$fr")" \
    "$(color "$seven" 80 90)" "$(bar "$seven")" "$reset" "$seven" "$(countdown "$sr")" \
    "$(color "$ctx" 70 80)"   "$(bar "$ctx")"   "$reset" "$ctx"
fi
