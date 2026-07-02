# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [1.0.0] — 2026-07-01

First public release.

### Added
- Two-line dashboard driven entirely by Claude Code's native status JSON (no log scraping).
- **Line 1 — identity:** model + effort (with escalating flare `▲ / ▲▲ / ◆◆◆`), a compact
  `∞` glyph for 1M-context models, current folder, and a full git segment.
- **Git segment:** branch (or short SHA when detached), a fork-glyph **worktree marker**
  auto-detected from git, and `↑ahead ↓behind +staged ✎modified …untracked`, collapsing to
  a green `✓` when clean.
- **Line 2 — telemetry:** context gauge scaled to the full window, 5-hour and weekly usage
  caps with reset countdowns, model-aware cost with a `·$X/h` burn-rate, line churn,
  and a session timer.
- Shared green→rust→red semantic ramp across every gauge, with tunable flip points.
- `install.sh` one-command installer (backs up any existing config), and an optional
  MountainLabs Ghostty theme in `examples/`.

[1.0.0]: https://github.com/ClearMountainDigital/mountainlabs-statusline/releases/tag/v1.0.0
