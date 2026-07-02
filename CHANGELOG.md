# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [1.1.0] — 2026-07-01

### Added
- **Agent spend** segment on line 2 (`agt 3·~$1.94 (46%)`): count of Task/Agent
  **subagents** this session, their summed cost, and the share of total session
  spend they represent. Subagents run in their own context window, so their cost
  never appears in the context gauge — this segment surfaces that otherwise
  invisible spend.
- Cost is summed from each subagent's transcript (`<session>/subagents/agent-*.jsonl`)
  and priced **per each line's own model** (subagents often run a cheaper model
  than the main thread), including the cache-write/read multipliers.
- The subagent parse is gated by a `count-mtime-size` signature and cached under
  `${XDG_CACHE_HOME:-~/.cache}/mountainlabs-statusline/`, so a busy session
  re-parses only when a subagent transcript changes — steady state is one
  `stat()` per file.

### Changed
- **Context bar is now an absolute-token gradient** instead of a percentage-zone
  flat fill. Each cell is colored by the tokens it represents: pure sage through
  the ~100k "smart zone" (`CTX_GOOD_TOK`), then a smooth sage → rust → red ramp
  that reaches full red by 400k (`CTX_RED_TOK`) and clamps. This flags context
  degradation on large windows where a percentage bar can't — 600k on a 1M window
  is only 60% but is deep in the "dumb zone." The 5h/weekly cap bars are unchanged
  (still the three-zone `_PCT` flip).
- **Accent palette re-tuned for contrast (a11y pass).** The old muted accents
  (`rust #8C4820`, `red #AD0000`, `sage #6E9678`, `dim`) were nearly unreadable
  as text/glyphs — the git status counts on the forest segment and the cost figure
  on a dark terminal both fell below WCAG minimums (e.g. `✎modified` measured a
  1.2:1 ratio). Brightened to `sage #96C8A5`, `rust #E28A4A`, `red #EE6C64`,
  `amber #D0AA68`, `dim #9E9E96`. Every informational element now clears its target
  — line-2 telemetry at AA (≥ 4.5:1) on the dark background, line-1 git counts and
  glyphs at the UI-component threshold (≥ 3.0:1) on their segment backgrounds. Hues
  are unchanged, so the sage → rust → red semantics and brand feel carry over.

### Fixed
- **Gauges never show an empty bar next to a live number.** Both the context bar
  and the 5h/weekly cap bars now floor to a 1-cell sliver whenever their value is
  above zero — previously any usage that rounded below one cell (e.g. 68k on a 1M
  window, or a 6% cap) drew an all-empty track, which read as broken. Zero still
  renders empty.

### Notes
- Agent-spend rates are a local estimate; keep the `agent_spend` pricing block in
  sync with [claude.com/pricing](https://claude.com/pricing).

[1.1.0]: https://github.com/ClearMountainDigital/mountainlabs-statusline/releases/tag/v1.1.0

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
