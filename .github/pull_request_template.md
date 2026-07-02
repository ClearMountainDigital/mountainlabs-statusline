<!-- Thanks for the PR! Keep it focused — one change per PR is easiest to review. -->

## What & why

<!-- What does this change, and what problem does it solve? -->

## How verified

<!-- Check what you ran. All should be green; CI runs the first two on Linux + macOS. -->

- [ ] `tests/run.sh` passes
- [ ] `tests/lint.sh` passes (shellcheck-clean)
- [ ] Goldens regenerated **and reviewed** if the output changed on purpose (`tests/run.sh --update`)
- [ ] Manual render checked (`echo '{...}' | ./statusline.sh`)

## Shell floor

- [ ] No bash-4-isms — stays bash 3.2 compatible (see `CONTRIBUTING.md`)
- [ ] Portable across BSD (macOS) and GNU (Linux) utilities

## Notes

<!-- Screenshots of the rendered line, follow-ups, or anything a reviewer should know. -->
