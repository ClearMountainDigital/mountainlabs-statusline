#!/usr/bin/env bash
# ============================================================================
# MountainLabs — Claude Code statusline          v1.0.0 · MIT · MountainLabs.ai
# https://github.com/ClearMountainDigital/mountainlabs-statusline
#
# A two-line live dashboard rendered above the Claude Code prompt:
#   Line 1 (identity):  model+effort · folder · git branch/worktree/status
#   Line 2 (telemetry): context · 5h/weekly caps · cost+burn · churn · timer
#
# Reads the native status JSON Claude Code streams on stdin — no log scraping
# and no estimates of our own; the same numbers the app itself reports.
#
# Requires: bash, jq, git, awk, date — plus a Nerd Font for the  branch /
#  folder /  worktree / powerline separator glyphs.
set -o pipefail
input="$(cat)"
j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

# ------------------------------------------------------------------ data ----
MODEL="$(j '.model.display_name // "Claude"')"
# detect + strip a "(1M context)" suffix; mark it so line 1 shows a compact ∞ glyph
HAS_1M=""; case "$MODEL" in *"(1M context)"*) HAS_1M=1; MODEL="${MODEL/ (1M context)/}";; esac
EFFORT="$(j '.effort.level // empty')"
DIR="$(j '.workspace.current_dir // .cwd // empty')"
WT="$(j '.workspace.git_worktree // .worktree.name // empty')"
COST="$(j '.cost.total_cost_usd // 0')"
DUR_MS="$(j '.cost.total_duration_ms // 0')"
ADDED="$(j '.cost.total_lines_added // 0')"
REMOVED="$(j '.cost.total_lines_removed // 0')"
CTX_PCT="$(j '.context_window.used_percentage // empty')"
IN_TOK="$(j '.context_window.total_input_tokens // 0')"
CTX_SIZE="$(j '.context_window.context_window_size // 200000')"
FIVE_H="$(j '.rate_limits.five_hour.used_percentage // empty')"
SEVEN_D="$(j '.rate_limits.seven_day.used_percentage // empty')"
FIVE_RESET="$(j '.rate_limits.five_hour.resets_at // empty')"
SEVEN_RESET="$(j '.rate_limits.seven_day.resets_at // empty')"
# fast mode is not in the documented statusline schema — shown only if it appears
FAST="$(j '.speed // .fast // empty')"

# -------------------------------------------------------------- tunables ----
# All gauges share one green→rust→red ramp. Flip points, as percentages:
CTX_WARN_PCT=70    # context + caps: sage -> rust at this % of the window/cap
CTX_DANGER_PCT=90  # ...             rust -> red  at this %
COST_WARN=5        # session cost:   sage -> rust at this many dollars
COST_DANGER=20     # ...             rust -> red  at this many dollars

# --------------------------------------------------------------- palette ----
# MountainLabs.ai / Clear Mountain Provisions
CREAM='242;242;242'; DARKB='38;20;10'
FOREST='63;81;71';  RUST='140;72;32'; STONE='113;106;86'
SLATE='73;91;108';  RED='173;0;0';    SAGE='110;150;120'
DIM='120;120;115'
SKY='150;180;205';  AMBER='201;142;71'; TRACK='64;64;60'   # readable accents + bar track

fg(){ printf '\033[38;2;%sm' "$1"; }
bg(){ printf '\033[48;2;%sm' "$1"; }
rs(){ printf '\033[0m'; }
SEP=$''   # powerline right-facing separator
GBR=$''   # git branch glyph
FLD=$''   # folder glyph
WTG=$''   # git-fork glyph (worktree)

# zone color for a 0-100 percentage
pct_color(){ p=${1%.*}; if [ "$p" -ge "$CTX_DANGER_PCT" ]; then printf '%s' "$RED";
             elif [ "$p" -ge "$CTX_WARN_PCT" ]; then printf '%s' "$RUST";
             else printf '%s' "$SAGE"; fi; }

fmt_tokens(){ awk -v t="$1" 'BEGIN{
  if(t>=1000000)printf "%.1fM",t/1000000;
  else if(t>=1000)printf "%dk",int(t/1000+0.5);
  else printf "%d",t }'; }

# zone color for a dollar amount (float-safe via awk): sage / rust / red by thresholds
cost_col(){ awk -v c="$1" -v w="$COST_WARN" -v d="$COST_DANGER" \
  -v sage="$SAGE" -v rust="$RUST" -v red="$RED" \
  'BEGIN{ if(c+0>=d)print red; else if(c+0>=w)print rust; else print sage }'; }

# compact "time until epoch $1" -> e.g. 3d11h, 2h13m, 47m, now
until_reset(){ local now diff d h m; now="$(date +%s)"; diff=$(( $1 - now ))
  [ "$diff" -le 0 ] && { printf 'now'; return; }
  d=$(( diff/86400 )); h=$(( (diff%86400)/3600 )); m=$(( (diff%3600)/60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  else printf '%dm' "$m"; fi; }

bar(){ # $1 fill(0..width) $2 width $3 fill-color
  local f=$1 w=$2 c=$3 i out=""
  for((i=0;i<w;i++)); do
    if (( i<f )); then out+="$(fg "$c")█"; else out+="$(fg "$TRACK")░"; fi
  done
  printf '%s%s' "$out" "$(rs)"; }

# ============================================================ LINE 1 ========
model_txt="${MODEL}"
[ -n "$HAS_1M" ] && model_txt="${model_txt} $(fg "$SKY")∞$(fg "$CREAM")"
[ -n "$EFFORT" ] && model_txt="${model_txt}·${EFFORT}"
case "$EFFORT" in
  high)  model_txt="${model_txt} $(fg "$SAGE")▲$(fg "$CREAM")" ;;
  xhigh) model_txt="${model_txt} $(fg "$RUST")▲▲$(fg "$CREAM")" ;;
  max)   model_txt="${model_txt} $(fg "$RED")◆◆◆$(fg "$CREAM")" ;;
esac
[ -n "$FAST" ] && model_txt="${model_txt} $(fg "$RUST")⚡$(fg "$CREAM")"

dir_txt="${FLD}  $(basename "${DIR:-?}")"

git_txt=""
if [ -n "$DIR" ] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH="$(git -C "$DIR" branch --show-current 2>/dev/null)"
  [ -z "$BRANCH" ] && BRANCH="$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null)"
  git_txt="${GBR}  ${BRANCH}"
  # worktree marker — Claude Code doesn't send a worktree field, so detect from git:
  # a linked worktree's private git-dir differs from the shared common git-dir.
  if [ -z "$WT" ]; then
    _gd="$(git -C "$DIR" rev-parse --git-dir 2>/dev/null)"
    _cd="$(git -C "$DIR" rev-parse --git-common-dir 2>/dev/null)"
    [ -n "$_gd" ] && [ "$_gd" != "$_cd" ] && WT="$(basename "$(dirname "$_cd")")"
  fi
  [ -n "$WT" ] && git_txt="${git_txt} $(fg "$DIM")${WTG} ${WT}$(fg "$CREAM")"
  ab="$(git -C "$DIR" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)"
  behind="$(printf '%s' "$ab" | awk '{print $1+0}')"
  ahead="$(printf '%s' "$ab" | awk '{print $2+0}')"
  staged="$(git -C "$DIR" diff --cached --numstat 2>/dev/null | grep -c '')"
  modified="$(git -C "$DIR" diff --numstat 2>/dev/null | grep -c '')"
  untracked="$(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null | grep -c '')"
  [ "${ahead:-0}" -gt 0 ]     && git_txt="${git_txt} $(fg "$SKY")↑${ahead}$(fg "$CREAM")"
  [ "${behind:-0}" -gt 0 ]    && git_txt="${git_txt} $(fg "$AMBER")↓${behind}$(fg "$CREAM")"
  [ "${staged:-0}" -gt 0 ]    && git_txt="${git_txt} $(fg "$SAGE")+${staged}$(fg "$CREAM")"
  [ "${modified:-0}" -gt 0 ]  && git_txt="${git_txt} $(fg "$RUST")✎${modified}$(fg "$CREAM")"
  [ "${untracked:-0}" -gt 0 ] && git_txt="${git_txt} $(fg "$DIM")…${untracked}$(fg "$CREAM")"
  if [ "${ahead:-0}${behind:-0}${staged:-0}${modified:-0}${untracked:-0}" = "00000" ]; then
    git_txt="${git_txt} $(fg "$SAGE")✓$(fg "$CREAM")"
  fi
fi

seg_txt=("$model_txt" "$dir_txt"); seg_bg=("$SLATE" "$STONE")
if [ -n "$git_txt" ]; then seg_txt+=("$git_txt"); seg_bg+=("$FOREST"); fi

line1=""; n=${#seg_txt[@]}
for ((i=0;i<n;i++)); do
  b="${seg_bg[i]}"
  line1+="$(bg "$b")$(fg "$CREAM") ${seg_txt[i]} "
  if ((i<n-1)); then
    line1+="$(bg "${seg_bg[i+1]}")$(fg "$b")${SEP}"
  else
    line1+="$(rs)$(fg "$b")${SEP}$(rs)"
  fi
done

# ============================================================ LINE 2 ========
# context
if [ -n "$CTX_PCT" ]; then
  cpct=${CTX_PCT%.*}
  # bar scales to the FULL context window (rounded so small usage still shows a sliver)
  fill=$(( (IN_TOK * 10 + CTX_SIZE / 2) / CTX_SIZE )); [ "$fill" -gt 10 ] && fill=10
  col="$(pct_color "$cpct")"
  ctx="$(fg "$DIM")ctx$(rs) $(bar "$fill" 10 "$col") $(fg "$col")$(fmt_tokens "$IN_TOK")$(fg "$DIM")/$(fmt_tokens "$CTX_SIZE")$(rs)"
else
  ctx="$(fg "$DIM")ctx —$(rs)"
fi

caps=""
if [ -n "$FIVE_H" ]; then
  c="$(pct_color "$FIVE_H")"
  caps+="   $(fg "$DIM")5h$(rs) $(bar $(( (${FIVE_H%.*} * 4 + 50) / 100 )) 4 "$c") $(fg "$c")${FIVE_H%.*}%$(rs)"
  [ -n "$FIVE_RESET" ] && caps+="$(fg "$DIM")·⟳$(until_reset "$FIVE_RESET")$(rs)"
fi
if [ -n "$SEVEN_D" ]; then
  c="$(pct_color "$SEVEN_D")"
  caps+="   $(fg "$DIM")wk$(rs) $(bar $(( (${SEVEN_D%.*} * 4 + 50) / 100 )) 4 "$c") $(fg "$c")${SEVEN_D%.*}%$(rs)"
  [ -n "$SEVEN_RESET" ] && caps+="$(fg "$DIM")·⟳$(until_reset "$SEVEN_RESET")$(rs)"
fi

cost="   $(fg "$(cost_col "$COST")")$(printf '~$%.2f' "$COST")$(rs)"
if [ "${DUR_MS:-0}" -gt 0 ]; then
  rate="$(awk -v c="$COST" -v ms="$DUR_MS" 'BEGIN{ printf "%.2f", c/(ms/3600000) }')"
  cost+="$(fg "$DIM") ·\$${rate}/h$(rs)"
fi

churn=""
if [ "${ADDED:-0}" -gt 0 ] || [ "${REMOVED:-0}" -gt 0 ]; then
  churn="   "
  [ "${ADDED:-0}" -gt 0 ]   && churn+="$(fg "$SAGE")+${ADDED}$(rs) "
  [ "${REMOVED:-0}" -gt 0 ] && churn+="$(fg "$RED")−${REMOVED}$(rs) "
  churn="${churn% }"
fi

secs=$(( DUR_MS / 1000 )); mins=$(( secs / 60 )); secs=$(( secs % 60 ))
timer="   $(fg "$DIM")${mins}m ${secs}s$(rs)"

line2="${ctx}${caps}${cost}${churn}${timer}"

printf '%s\n%s\n' "$line1" "$line2"
