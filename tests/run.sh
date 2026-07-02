#!/usr/bin/env bash
# ============================================================================
# MountainLabs statusline — golden-output test harness  (issue #0001)
#
#   tests/run.sh                 run all fixtures, diff against goldens
#   tests/run.sh <name>          run a single fixture (e.g. git-dirty)
#   tests/run.sh --update        regenerate all goldens
#   tests/run.sh --update <name> regenerate one golden
#
# Each fixture in tests/fixtures/*.json is piped through statusline.sh; the
# output has ANSI stripped and is diffed against tests/golden/<name>.txt.
# The environment is frozen (clock, git identity/dates, HOME/XDG, git config)
# so output is deterministic on any machine. See tests/README.md.
# ============================================================================
set -u

SELF="${BASH_SOURCE[0]:-$0}"
TESTS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
STATUSLINE="$ROOT/statusline.sh"
FIXDIR="$TESTS_DIR/fixtures"
GOLDDIR="$TESTS_DIR/golden"

UPDATE=0
if [ "${1:-}" = "--update" ]; then UPDATE=1; shift; fi
ONLY="${1:-}"

# ---- deterministic environment --------------------------------------------
NOW=1767225600                       # 2026-01-01T00:00:00Z — the frozen "now"
export LC_ALL=C
export GIT_AUTHOR_NAME='MountainLabs Test' GIT_AUTHOR_EMAIL='test@mountainlabs.test'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_AUTHOR_DATE='2026-01-01T00:00:00 +0000'
export GIT_COMMITTER_DATE='2026-01-01T00:00:00 +0000'
# ignore the developer's global/system git config so init.defaultBranch,
# object format (sha1), gpgsign, aliases, etc. can't leak into the goldens
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/mlsl-tests.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT
# stop git from discovering any real repo above the temp workspaces
export GIT_CEILING_DIRECTORIES="$TMPROOT"
# isolate the agent-spend on-disk cache
export XDG_CACHE_HOME="$TMPROOT/cache"
# isolate user config (#0007) so a real ~/.config file can't leak into goldens;
# per-fixture <name>.env files may point MOUNTAINLABS_STATUSLINE_CONFIG at a
# committed sample conf, referenced via the exported $ROOT.
export XDG_CONFIG_HOME="$TMPROOT/config"
unset MOUNTAINLABS_STATUSLINE_CONFIG
export ROOT

# Freeze `date +%s` via a PATH shim so the 5h/weekly reset countdowns are stable.
# statusline.sh calls `date` only as `date +%s`; anything else falls through.
REALDATE="$(command -v date)"
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/date" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "+%s" ]; then echo $NOW; exit 0; fi
exec "$REALDATE" "\$@"
EOF
chmod +x "$TMPROOT/bin/date"
export PATH="$TMPROOT/bin:$PATH"

ESC=$'\033'
strip_ansi(){ LC_ALL=C sed "s/${ESC}\[[0-9;]*m//g"; }

# ---- git fixture builders --------------------------------------------------
# Each silences all git chatter and echoes ONLY the workspace path to render.
ginit(){ git -C "$1" init -q >/dev/null 2>&1; }

mk_repo_clean(){
  local d="$TMPROOT/git-clean/my-project"; mkdir -p "$d"
  ginit "$d"
  printf 'base\n' > "$d/README.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm base >/dev/null 2>&1
  git -C "$d" branch -M main >/dev/null 2>&1
  echo "$d"
}

mk_repo_detached(){
  local d="$TMPROOT/git-detached/my-project"; mkdir -p "$d"
  ginit "$d"
  printf 'a\n' > "$d/README.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm a >/dev/null 2>&1
  printf 'b\n' >> "$d/README.md"
  git -C "$d" commit -aqm b >/dev/null 2>&1
  git -C "$d" branch -M main >/dev/null 2>&1
  git -C "$d" checkout -q HEAD~1 >/dev/null 2>&1   # detach at first commit
  echo "$d"
}

mk_repo_worktree(){
  local main="$TMPROOT/git-worktree/my-project" wt="$TMPROOT/git-worktree/feature-wt"
  mkdir -p "$main"
  ginit "$main"
  printf 'base\n' > "$main/README.md"
  git -C "$main" add -A >/dev/null 2>&1
  git -C "$main" commit -qm base >/dev/null 2>&1
  git -C "$main" branch -M main >/dev/null 2>&1
  git -C "$main" worktree add -q -b feature "$wt" >/dev/null 2>&1
  echo "$wt"
}

mk_repo_rename(){
  # a STAGED rename — porcelain v2 emits a type "2" (R.) entry, which no other
  # fixture produces; guards the v2 parser added in #0006. Counts as staged=1.
  local d="$TMPROOT/git-rename/my-project"; mkdir -p "$d"
  ginit "$d"
  printf 'contents\n' > "$d/oldname.txt"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm base >/dev/null 2>&1
  git -C "$d" branch -M main >/dev/null 2>&1
  git -C "$d" mv oldname.txt newname.txt >/dev/null 2>&1
  echo "$d"
}

mk_repo_untracked_dir(){
  # a clean repo plus an untracked DIRECTORY holding 3 files. Guards #0006's use
  # of --untracked-files=all: git status would otherwise collapse the dir to one
  # "?" entry (=> "…1"), while the old `ls-files --others` counted each file
  # (=> "…3"). The expected render is "…3", so this fixture fails if the flag is dropped.
  local d="$TMPROOT/git-untracked-dir/my-project"; mkdir -p "$d"
  ginit "$d"
  printf 'base\n' > "$d/README.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm base >/dev/null 2>&1
  git -C "$d" branch -M main >/dev/null 2>&1
  mkdir -p "$d/notes"
  printf 'a\n' > "$d/notes/a.txt"; printf 'b\n' > "$d/notes/b.txt"; printf 'c\n' > "$d/notes/c.txt"
  echo "$d"
}

mk_repo_dirty(){
  local root="$TMPROOT/git-dirty"
  local bare="$root/origin.git" work="$root/my-project" rc="$root/remoteclone"
  mkdir -p "$root"
  git init -q --bare "$bare" >/dev/null 2>&1
  git clone -q "$bare" "$work" >/dev/null 2>&1
  printf 'base\n' > "$work/f.txt"
  git -C "$work" add -A >/dev/null 2>&1
  git -C "$work" commit -qm base >/dev/null 2>&1
  git -C "$work" branch -M main >/dev/null 2>&1
  git -C "$work" push -q -u origin main >/dev/null 2>&1
  # two remote-only commits (local will be 2 behind after fetch)
  git clone -q "$bare" "$rc" >/dev/null 2>&1
  printf 'r1\n' >> "$rc/f.txt"; git -C "$rc" commit -aqm r1 >/dev/null 2>&1
  printf 'r2\n' >> "$rc/f.txt"; git -C "$rc" commit -aqm r2 >/dev/null 2>&1
  git -C "$rc" push -q origin main >/dev/null 2>&1
  # one local-only commit (1 ahead)
  printf 'localextra\n' > "$work/g.txt"
  git -C "$work" add g.txt >/dev/null 2>&1
  git -C "$work" commit -qm local >/dev/null 2>&1
  git -C "$work" fetch -q >/dev/null 2>&1
  # working-tree state: 1 modified (tracked), 1 staged (new), 1 untracked
  printf 'modified\n' >> "$work/f.txt"
  printf 'staged\n' > "$work/staged.txt"; git -C "$work" add staged.txt >/dev/null 2>&1
  printf 'x\n' > "$work/untracked.txt"
  echo "$work"
}

mk_agent_transcript(){
  local base="$TMPROOT/agent-spend/session.jsonl"
  local sub="$TMPROOT/agent-spend/session/subagents"
  mkdir -p "$sub"
  {
    printf '%s\n' '{"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":2000,"cache_read_input_tokens":5000,"cache_creation_input_tokens":3000}}}'
    printf '%s\n' '{"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":500,"output_tokens":800}}}'
  } > "$sub/agent-1.jsonl"
  echo "$base"
}

# ---- payload assembly ------------------------------------------------------
build_payload(){  # $1 fixture name -> final JSON on stdout
  local name="$1" base ws tp
  base="$(cat "$FIXDIR/$name.json")"
  case "$name" in
    empty)         printf '%s' "$base"; return 0 ;;
    git-clean)     ws="$(mk_repo_clean)" ;;
    git-dirty)     ws="$(mk_repo_dirty)" ;;
    git-detached)  ws="$(mk_repo_detached)" ;;
    git-worktree)  ws="$(mk_repo_worktree)" ;;
    git-rename)    ws="$(mk_repo_rename)" ;;
    git-untracked-dir) ws="$(mk_repo_untracked_dir)" ;;
    agent-spend)
        ws="$TMPROOT/agent-spend"; mkdir -p "$ws"
        tp="$(mk_agent_transcript)"
        base="$(printf '%s' "$base" | jq --arg tp "$tp" '.transcript_path=$tp')"
        ;;
    *)             ws="$TMPROOT/$name"; mkdir -p "$ws" ;;
  esac
  printf '%s' "$base" | jq --arg d "$ws" '.workspace.current_dir=$d'
}

# ---- run -------------------------------------------------------------------
mkdir -p "$GOLDDIR"
pass=0; fail=0; upd=0
for fx in "$FIXDIR"/*.json; do
  name="$(basename "$fx" .json)"
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue
  gold="$GOLDDIR/$name.txt"
  # An optional <name>.env is sourced (exported) only for that fixture, so a case
  # can exercise env-var / config-file overrides (#0007). Absent = plain run.
  envfile="$FIXDIR/$name.env"
  out="$(build_payload "$name" | (
    # shellcheck disable=SC1090  # per-fixture override file, path is dynamic
    [ -f "$envfile" ] && { set -a; . "$envfile"; set +a; }
    exec "$STATUSLINE"
  ) | strip_ansi)"

  if [ "$UPDATE" = 1 ]; then
    printf '%s\n' "$out" > "$gold"
    printf 'UPDATED  %s\n' "$name"; upd=$((upd + 1)); continue
  fi
  if [ ! -f "$gold" ]; then
    printf 'MISSING  %s  (run: tests/run.sh --update %s)\n' "$name" "$name"
    fail=$((fail + 1)); continue
  fi
  if [ "$out" = "$(cat "$gold")" ]; then
    printf 'PASS     %s\n' "$name"; pass=$((pass + 1))
  else
    printf 'FAIL     %s\n' "$name"
    diff <(cat "$gold") <(printf '%s\n' "$out") | sed 's/^/         /'
    fail=$((fail + 1))
  fi
done

if [ -n "$ONLY" ] && [ "$((pass + fail + upd))" -eq 0 ]; then
  printf 'No fixture named "%s" in %s\n' "$ONLY" "$FIXDIR"; exit 2
fi
if [ "$UPDATE" = 1 ]; then printf '\nUpdated %d golden(s).\n' "$upd"; exit 0; fi
printf '\n%d passed, %d failed.\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
