#!/usr/bin/env bash
# ============================================================================
# MountainLabs — Claude Code statusline          v1.1.0 · MIT · MountainLabs.ai
# https://github.com/ClearMountainDigital/mountainlabs-statusline
#
# A two-line live dashboard rendered above the Claude Code prompt:
#   Line 1 (identity):  model+effort · folder · git branch/worktree/status
#   Line 2 (telemetry): context · 5h/weekly caps · cost+burn · agent spend · churn · timer
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
# transcript + session id: used to locate this session's subagent transcripts
TRANSCRIPT="$(j '.transcript_path // empty')"
SESSION="$(j '.session_id // empty')"

# -------------------------------------------------------------- tunables ----
# The 5h/weekly cap bars flip in three zones, as % of the cap:
CTX_WARN_PCT=70    # caps: sage -> rust at this % of the cap
CTX_DANGER_PCT=90  # caps: rust -> red  at this %
# The context bar is a smooth gradient keyed on ABSOLUTE tokens (not % of window):
# quality degrades past ~100k regardless of a 1M window, so color follows tokens.
CTX_GOOD_TOK=100000  # end of the "smart zone" — pure sage up to here
CTX_RED_TOK=400000   # tokens at which the bar hits full red, then clamps (dumb zone)
COST_WARN=5        # session cost:   sage -> rust at this many dollars
COST_DANGER=20     # ...             rust -> red  at this many dollars

# --------------------------------------------------------------- palette ----
# MountainLabs.ai / Clear Mountain Provisions
# Accent hues are tuned for contrast: FOREST/STONE/SLATE are line-1 segment
# BACKGROUNDS; the rest are FOREGROUNDS that must stay legible both on those
# mid-tone backgrounds (WCAG 1.4.11 UI ≥3.0) and on a dark terminal (AA ≥4.5).
CREAM='242;242;242'
FOREST='63;81;71';  RUST='226;138;74'; STONE='113;106;86'
SLATE='73;91;108';  RED='238;108;100';  SAGE='150;200;165'
DIM='158;158;150'
SKY='150;180;205';  AMBER='208;170;104'; TRACK='64;64;60'   # readable accents + bar track

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

# portable stat: BSD (-f) then GNU (-c); emits "<mtime> <size>" per file
_stat_ms(){ stat -f '%m %z' "$@" 2>/dev/null || stat -c '%Y %s' "$@" 2>/dev/null; }

# Subagent spend. Task/Agent subagents run in their OWN context window, so their
# work never lands in the ctx gauge above — but Claude Code still bills it. Each
# subagent gets its own transcript at <session>/subagents/agent-*.jsonl; we sum
# message.usage across them, priced per each line's own model (agents often run a
# cheaper model than the main thread). Emits "<count> <cost_usd>".
#
# Rates below are per-MTok base input / output; cache is a multiple of base input
# (5m write ×1.25, 1h write ×2, read ×0.1). Keep in sync with claude.com/pricing.
# Parsing is gated by a cheap file signature + on-disk cache so a busy session
# doesn't re-parse every render — steady state is one stat() per file.
agent_spend(){ # $1 subagents dir  $2 cache file
  local dir="$1" cache="$2" sig cached_sig cached_val val n; local files
  sig="$(_stat_ms "$dir"/*.jsonl 2>/dev/null | awk '{m=($1>m)?$1:m;s+=$2;n++}END{print n"-"m"-"s}')"
  case "$sig" in ''|0-*) printf '0 0'; return;; esac
  if [ -r "$cache" ]; then IFS='|' read -r cached_sig cached_val < "$cache"; fi
  if [ "$sig" = "$cached_sig" ] && [ -n "$cached_val" ]; then printf '%s' "$cached_val"; return; fi
  # the sig guard above guarantees at least one .jsonl, so the glob never stays literal
  files=( "$dir"/*.jsonl ); n=${#files[@]}
  val="$(
    for f in "${files[@]}"; do
      jq -rc 'select(.type=="assistant") | .message as $m | [
          ($m.model // "unknown"),
          ($m.usage.input_tokens // 0), ($m.usage.output_tokens // 0),
          ($m.usage.cache_read_input_tokens // 0),
          ($m.usage.cache_creation.ephemeral_5m_input_tokens // 0),
          ($m.usage.cache_creation.ephemeral_1h_input_tokens // 0),
          ($m.usage.cache_creation_input_tokens // 0)] | @tsv' "$f" 2>/dev/null
    done | awk -F'\t' -v n="$n" '
      function rates(mo){
        if(mo ~ /haiku-3/){bi=0.8;bo=4}
        else if(mo ~ /haiku/){bi=1;bo=5}
        else if(mo ~ /fable|mythos/){bi=10;bo=50}
        else if(mo ~ /opus-4-(5|6|7|8)/){bi=5;bo=25}
        else if(mo ~ /opus/){bi=15;bo=75}          # Opus 4.1 and earlier
        else if(mo ~ /sonnet-5/){bi=2;bo=10}       # intro pricing thru 2026-08-31
        else if(mo ~ /sonnet/){bi=3;bo=15}
        else {bi=3;bo=15} }
      { mo=$1;inp=$2;out=$3;cr=$4;c5=$5;c1=$6;cctot=$7
        if(c5==0 && c1==0) c5=cctot               # fallback: treat unknown cache as 5m
        rates(mo); tot+=(inp*bi+cr*bi*0.1+c5*bi*1.25+c1*bi*2+out*bo)/1e6 }
      END{ printf "%d %.2f", n+0, tot+0 }'
  )"
  [ -z "$val" ] && val="0 0"
  mkdir -p "$(dirname "$cache")" 2>/dev/null
  printf '%s|%s\n' "$sig" "$val" > "$cache" 2>/dev/null
  printf '%s' "$val"; }

bar(){ # $1 fill(0..width) $2 width $3 fill-color
  local f=$1 w=$2 c=$3 i out=""
  for((i=0;i<w;i++)); do
    if (( i<f )); then out+="$(fg "$c")█"; else out+="$(fg "$TRACK")░"; fi
  done
  printf '%s%s' "$out" "$(rs)"; }

# ramp color for an absolute token count -> "R;G;B": pure sage <= CTX_GOOD_TOK,
# then sage->rust->red across [CTX_GOOD_TOK, CTX_RED_TOK], clamped to red beyond.
grad_color(){ # $1 tokens
  awk -v t="$1" -v good="$CTX_GOOD_TOK" -v redt="$CTX_RED_TOK" \
      -v sage="$SAGE" -v rust="$RUST" -v red="$RED" 'BEGIN{
    split(sage,s,";");split(rust,u,";");split(red,r,";"); if(redt<=good)redt=good+1;
    if(t<=good){printf "%d;%d;%d",s[1],s[2],s[3];exit}
    fr=(t-good)/(redt-good); if(fr>1)fr=1; if(fr<0)fr=0;
    if(fr<=0.5){k=fr/0.5; printf "%d;%d;%d",s[1]+(u[1]-s[1])*k+.5,s[2]+(u[2]-s[2])*k+.5,s[3]+(u[3]-s[3])*k+.5}
    else       {k=(fr-0.5)/0.5; printf "%d;%d;%d",u[1]+(r[1]-u[1])*k+.5,u[2]+(r[2]-u[2])*k+.5,u[3]+(r[3]-u[3])*k+.5} }'; }

# gradient bar: each filled cell is colored by the token position IT represents,
# so a partly-full bar visibly warms as it reaches into the dumb zone. One awk call.
bar_grad(){ # $1 fill(0..width) $2 width $3 scale-tokens (context window size)
  awk -v f="$1" -v w="$2" -v mx="$3" -v good="$CTX_GOOD_TOK" -v redt="$CTX_RED_TOK" \
      -v sage="$SAGE" -v rust="$RUST" -v red="$RED" -v track="$TRACK" 'BEGIN{
    split(sage,s,";");split(rust,u,";");split(red,r,";"); esc=sprintf("%c[",27); if(redt<=good)redt=good+1;
    for(i=0;i<w;i++){
      if(i<f){
        tok=(i*mx)/w + (mx/w)/2;                       # tokens at the center of this cell
        if(tok<=good){R=s[1];G=s[2];B=s[3]}
        else{ fr=(tok-good)/(redt-good); if(fr>1)fr=1; if(fr<0)fr=0;
          if(fr<=0.5){k=fr/0.5; R=s[1]+(u[1]-s[1])*k;G=s[2]+(u[2]-s[2])*k;B=s[3]+(u[3]-s[3])*k}
          else       {k=(fr-0.5)/0.5; R=u[1]+(r[1]-u[1])*k;G=u[2]+(r[2]-u[2])*k;B=u[3]+(r[3]-u[3])*k} }
        printf "%s38;2;%d;%d;%dm█", esc, R+.5,G+.5,B+.5;
      } else printf "%s38;2;%sm░", esc, track;
    }
    printf "%s0m", esc; }'; }

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
  # bar scales to the FULL context window (rounded so small usage still shows a sliver);
  # color is an absolute-token gradient — green in the smart zone, warming into the dumb zone.
  fill=$(( (IN_TOK * 10 + CTX_SIZE / 2) / CTX_SIZE )); [ "$fill" -gt 10 ] && fill=10
  # floor: any nonzero usage shows at least a 1-cell sliver (never an empty bar next to a live number)
  [ "$fill" -lt 1 ] && [ "${IN_TOK:-0}" -gt 0 ] && fill=1
  col="$(grad_color "$IN_TOK")"
  ctx="$(fg "$DIM")ctx$(rs) $(bar_grad "$fill" 10 "$CTX_SIZE") $(fg "$col")$(fmt_tokens "$IN_TOK")$(fg "$DIM")/$(fmt_tokens "$CTX_SIZE")$(rs)"
else
  ctx="$(fg "$DIM")ctx —$(rs)"
fi

# same 1-cell floor as the context bar: a live percentage never shows an empty gauge
cap_fill(){ f=$(( (${1%.*} * 4 + 50) / 100 )); [ "$f" -lt 1 ] && [ "${1%.*}" -gt 0 ] && f=1; printf '%s' "$f"; }
caps=""
if [ -n "$FIVE_H" ]; then
  c="$(pct_color "$FIVE_H")"
  caps+="   $(fg "$DIM")5h$(rs) $(bar "$(cap_fill "$FIVE_H")" 4 "$c") $(fg "$c")${FIVE_H%.*}%$(rs)"
  [ -n "$FIVE_RESET" ] && caps+="$(fg "$DIM") ($(until_reset "$FIVE_RESET"))$(rs)"
fi
if [ -n "$SEVEN_D" ]; then
  c="$(pct_color "$SEVEN_D")"
  caps+="   $(fg "$DIM")wk$(rs) $(bar "$(cap_fill "$SEVEN_D")" 4 "$c") $(fg "$c")${SEVEN_D%.*}%$(rs)"
  [ -n "$SEVEN_RESET" ] && caps+="$(fg "$DIM") ($(until_reset "$SEVEN_RESET"))$(rs)"
fi

cost="   $(fg "$(cost_col "$COST")")$(printf '~$%.2f' "$COST")$(rs)"
if [ "${DUR_MS:-0}" -gt 0 ]; then
  rate="$(awk -v c="$COST" -v ms="$DUR_MS" 'BEGIN{ printf "%.2f", c/(ms/3600000) }')"
  cost+="$(fg "$DIM") ·\$${rate}/h$(rs)"
fi

# agent spend — cost of Task/Agent subagents this session. It lives here next to
# cost (not context) on purpose: agents burn dollars but almost nothing lands in
# the ctx gauge, so this segment is what explains a rising bill beside a flat ctx.
agents=""
if [ -n "$TRANSCRIPT" ]; then
  _subdir="${TRANSCRIPT%.jsonl}/subagents"
  if [ -d "$_subdir" ]; then
    _cache="${XDG_CACHE_HOME:-$HOME/.cache}/mountainlabs-statusline/${SESSION:-default}.agents"
    read -r acount acost < <(agent_spend "$_subdir" "$_cache")
    if [ "${acount:-0}" -gt 0 ]; then
      acol="$(cost_col "$acost")"
      agents="   $(fg "$DIM")agt$(rs) $(fg "$acol")${acount}$(fg "$DIM")·$(fg "$acol")$(printf '~$%.2f' "$acost")$(rs)"
      # share of total session spend the agents account for — the "invisible" cost
      pctspend="$(awk -v a="$acost" -v c="$COST" 'BEGIN{ if(c+0>0){p=a/c*100; if(p>100)p=100; printf "%d",p+0.5} else print 0 }')"
      [ "${pctspend:-0}" -gt 0 ] && agents+="$(fg "$DIM") (${pctspend}%)$(rs)"
    fi
  fi
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

line2="${ctx}${caps}${cost}${agents}${churn}${timer}"

printf '%s\n%s\n' "$line1" "$line2"
