# Contributing

Thanks for helping improve MountainLabs statusline. It's one bash script and a golden
test harness, so the contribution loop is short: change the script, keep the tests and
lint green, update the goldens if the output changed on purpose.

## Setup

You need `bash`, `git`, `awk`, `date`, and [`jq`](https://jqlang.github.io/jq/). On
macOS everything but `jq` is preinstalled (`brew install jq`). [`shellcheck`](https://www.shellcheck.net/)
is needed for the lint step (`brew install shellcheck`).

## Run the tests and the linter

Both must be green before you open a PR — CI runs the same two on Linux and macOS.

```sh
tests/run.sh                     # run all golden tests
tests/run.sh git-dirty           # run one test by name
tests/lint.sh                    # shellcheck every shell script
echo '{}' | ./statusline.sh      # render once by hand with a payload
```

## Keep the goldens updated

Each `tests/fixtures/*.json` is a fake stdin payload; the harness pipes it in, strips
color codes, and diffs the text against `tests/golden/<name>.txt`. If your change alters
the output **on purpose**, regenerate the goldens and review the diff — it's the record
of what your change did:

```sh
tests/run.sh --update            # regenerate all goldens
tests/run.sh --update git-dirty  # regenerate one
```

Goldens strip ANSI, so they check layout and text, not color bytes. If you change
coloring, verify the escapes separately (see `tests/README.md`). If a test fails and the
change was **not** intended, fix the code, not the golden.

## Supported shells and utilities

- **bash 3.2** is the floor. macOS still ships bash 3.2, so avoid bash-4-isms:
  no associative arrays (`declare -A`), no `${var^^}`/`${var,,}` case conversion,
  no `|&`, no `mapfile`/`readarray`, no negative array indexing. Plain arrays,
  `${var/x/y}` substitution, and `(( ))` arithmetic are fine — they work in 3.2.
- **Portable utilities.** Assume both BSD (macOS) and GNU (Linux) `awk`, `sed`, `date`,
  and `stat`. Where the flags differ (e.g. `stat -f` vs `stat -c`), try one then fall
  back to the other, as `statusline.sh` already does.
- Keep it `shellcheck`-clean. If you must suppress a check, add a scoped
  `# shellcheck disable=` with a one-line reason.

## Comments

Comment the **why**, not the **what** — the purpose of a block and any non-obvious
gotcha, in plain prose. Skip comments that just restate the code. See `CLAUDE.md` for
the full style note.

## Commits and PRs

- Keep commits focused; write a clear subject line.
- Describe what changed and how you verified it (tests, lint, a manual render).
- Filing a bug or a feature idea instead? Use the issue forms — they'll prompt you for
  the details we need (your OS, bash version, terminal/font, and a payload to reproduce).
