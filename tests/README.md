# Tests

Golden-output tests for `statusline.sh` (issue [#0001](../issues/0001-golden-test-harness.md)).

Each fixture in `fixtures/*.json` is a stdin payload. The harness pipes it through
`statusline.sh`, strips ANSI color codes, and diffs the result against the matching
`golden/<name>.txt`. Because the rendered bar is a pure function of its input, this
catches any accidental change to the `jq` / `awk` / `git` render logic.

## Running

```sh
tests/run.sh                    # run every fixture; non-zero exit on any drift
tests/run.sh git-dirty          # run one fixture
tests/run.sh --update           # regenerate all goldens (after an intended change)
tests/run.sh --update git-dirty # regenerate one golden
```

Dependencies: `bash`, `jq`, `git`, `awk`, `sed`. No network.

## Linting

```sh
tests/lint.sh          # shellcheck over every shell script (needs shellcheck)
```

Run it before committing a shell change; CI runs the same command. The scripts are
kept shellcheck-clean — any `# shellcheck disable=...` directive must carry a one-line
justification.

## Workflow

1. Change `statusline.sh`.
2. Run `tests/run.sh`. A `FAIL` prints a diff of golden (`<`) vs. current (`>`).
3. If the change was **intended**, run `tests/run.sh --update` and **review the
   golden diff in your commit** — that diff is the human-readable record of what your
   change did to the output. If it was a regression, fix the code instead.

## How determinism is guaranteed

The bar embeds a clock, git state, and cost math, so the harness freezes everything
that would otherwise vary per machine or per run (see the environment block in
`run.sh`):

- **Clock** — a `date` PATH shim pins `date +%s` to `2026-01-01T00:00:00Z`, so the
  5h/weekly reset countdowns (`(2h13m)`, `(3d11h)`) are stable. Reset epochs in the
  cap fixtures are chosen relative to that instant.
- **Git** — git fixtures (`git-*`) build real repos in a temp dir with a fixed
  identity and fixed author/committer dates, so even the detached-HEAD short SHA is
  reproducible. `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` are neutered so the
  developer's own git config (default branch, object format, signing) can't leak in;
  `GIT_CEILING_DIRECTORIES` stops git from discovering a real repo above the temp
  workspace.
- **Paths** — only directory *basenames* appear in the output, and the temp repos use
  fixed names (`my-project`, `feature-wt`), so no absolute path reaches a golden.
- **Agent spend** — a synthetic subagent transcript with fixed token counts; the cost
  cache is redirected to a temp `XDG_CACHE_HOME`.

Assumption: git uses its default **SHA-1** object format (only the `git-detached`
short SHA depends on this). Neutering the global config makes that the effective
default on essentially every git build.

## Coverage

| Fixture | Exercises |
|---|---|
| `empty` | Empty `{}` payload — graceful degradation (`Claude`, `ctx —`, no git) |
| `no-git` | Folder segment present, git segment absent |
| `model-1m` | 1M-context `∞` glyph + `high ▲`; mirrors the README example |
| `model-standard` | Standard model name |
| `effort-high` / `-xhigh` / `-max` | Effort glyphs `▲` / `▲▲` / `◆◆◆` |
| `effort-medium` | Effort text with **no** glyph (low/medium branch) |
| `caps-present` | 5h/weekly bars in warn + danger zones, with reset countdowns |
| `caps-absent` | No `rate_limits` (API billing); cost in the danger zone |
| `context-dumb-zone` | 620k/1.0M — token gradient warmed into the "dumb zone" |
| `agent-spend` | Subagent transcript → `agt N·~$X (Y%)` segment |
| `git-clean` | Clean repo → `✓` |
| `git-dirty` | `↑1 ↓2 +1 ✎1 …1` (ahead/behind + staged/modified/untracked) |
| `git-detached` | Detached HEAD → short SHA |
| `git-worktree` | Linked worktree → fork marker + parent repo name |
| `git-rename` | Staged rename → porcelain-v2 type `2` (`R.`) entry → `+1` |
| `git-untracked-dir` | Untracked directory of 3 files → `…3` (guards `--untracked-files=all`) |
