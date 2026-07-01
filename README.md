<div align="center">

# MountainLabs Statusline

**A two-line live dashboard for [Claude Code](https://claude.com/claude-code) — model, git, context, usage caps, and cost, right above your prompt.**

[![License: MIT](https://img.shields.io/badge/License-MIT-3f5147.svg)](LICENSE)
[![Shell: bash](https://img.shields.io/badge/shell-bash-8c4820.svg)](statusline.sh)
[![Platform: macOS · Linux](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Linux-716a56.svg)](#requirements)
[![Made for Claude Code](https://img.shields.io/badge/made%20for-Claude%20Code-495b6c.svg)](https://claude.com/claude-code)

![MountainLabs statusline preview](assets/preview.svg)

</div>

---

Every render, Claude Code streams a JSON blob of live session state to your statusline command. Most statuslines throw most of it away. This one renders it — **the real numbers the app itself uses**, not estimates scraped from log files after the fact.

The result is a calm, information-dense bar in the warm **[MountainLabs.ai](https://mountainlabs.ai)** palette: identity on top, telemetry below.

```
 Opus 4.8 ∞·high ▲    makersmanager    main ↓6
ctx ███░░░░░░░ 68k/1.0M   5h ░░░░ 6%·⟳2h13m   wk ░░░░ 1%·⟳3d11h   ~$2.62 ·$0.63/h   +5   4m 9s
```

---

## Features

**Line 1 — identity** (warm powerline segments)
- **Model + effort** with escalating flair — `high ▲`, `xhigh ▲▲`, `max ◆◆◆`; a compact `∞` marks a 1M-context model.
- **Folder** — the current working directory.
- **Git** — branch (or short SHA when detached), a **worktree marker** auto-detected from git, and `↑ahead ↓behind +staged ✎modified …untracked`. A clean repo collapses to a single green `✓`.

**Line 2 — telemetry** (semantic green → rust → red ramp)
- **Context gauge** — a bar scaled to the full context window plus `used / total` tokens.
- **Usage caps** — your rolling **5-hour** and **weekly** limits, each with a `⟳` **reset countdown** (Pro/Max plans; auto-hidden on pay-as-you-go API billing).
- **Cost** — the model-aware session estimate, colored by size, with a live **`·$/h` burn rate**.
- **Churn** — lines added / removed this session.
- **Timer** — session wall-clock.

> [!NOTE]
> It reads **only** what Claude Code sends on stdin — no background daemons, no log parsing, nothing to keep in sync. When the CLI's numbers change, so does the bar.

---

## Install

**One-liner** (downloads the script, wires up `settings.json`, backs up anything it replaces):

```sh
curl -fsSL https://raw.githubusercontent.com/ClearMountainDigital/mountainlabs-statusline/main/install.sh | bash
```

**From a clone:**

```sh
git clone https://github.com/ClearMountainDigital/mountainlabs-statusline.git
cd mountainlabs-statusline
./install.sh
```

**Manual** (three steps):

1. Copy `statusline.sh` to `~/.claude/statusline.sh` and `chmod +x` it.
2. Add the `statusLine` block from [`examples/settings.json`](examples/settings.json) to your `~/.claude/settings.json`.
3. Restart Claude Code.

Then set your terminal font to a [Nerd Font](https://www.nerdfonts.com/) so the glyphs render (see [Requirements](#requirements)).

---

## Requirements

| Need | Why | Install (macOS) |
|---|---|---|
| `bash`, `git`, `awk`, `date` | Core rendering + git state | Preinstalled |
| `jq` | Parse the status JSON | `brew install jq` |
| A **Nerd Font** | The ` branch`, ` folder`, ` worktree`, and `` powerline glyphs | `brew install --cask font-jetbrains-mono-nerd-font` |

Works on **macOS** and **Linux**, in any terminal. Set your terminal's font to the installed Nerd Font (e.g. `JetBrainsMono Nerd Font`).

---

## Anatomy

**Line 1 — identity**

| Piece | Looks like | Notes |
|---|---|---|
| Model + effort | `Opus 4.8 ∞·high ▲` | `∞` = 1M-context model. Effort flair: `high ▲` · `xhigh ▲▲` · `max ◆◆◆`; `low`/`medium` stay quiet. |
| Folder | ` makersmanager` | Current directory name. |
| Branch | ` main` | Short SHA when in detached HEAD. |
| Worktree | ` makersmanager` | Fork glyph + parent repo — shown **only** inside a linked git worktree. |
| Git status | `↑2 ↓6 +1 ✎3 …4` / `✓` | ahead · behind · staged · modified · untracked. Each part appears only when non-zero; all-clean shows `✓`. |

**Line 2 — telemetry**

| Piece | Looks like | Notes |
|---|---|---|
| Context | `ctx ███░░░░░░░ 68k/1.0M` | Bar scaled to the full window; colored by % used. Shows `ctx —` until the CLI reports usage (never a fake `0%`). |
| 5h / weekly caps | `5h ░░░░ 6%·⟳2h13m` | Usage against your rolling caps + time to reset. Pro/Max only. |
| Cost | `~$2.62 ·$0.63/h` | Model-aware estimate (`~` = estimate, not a bill) + burn rate. |
| Churn | `+5 −0` → `+5` | Lines added / removed; zero sides are hidden. |
| Timer | `4m 9s` | Session wall-clock. |

---

## Palette — MountainLabs.ai

The palette *is* the semantics: identity segments use warm brand hues, and every gauge shares one **forest → rust → red = safe → warning → danger** ramp, so a warning reads as a warning at a glance.

| Role | Hex | | Role | Hex |
|---|---|---|---|---|
| Foreground | `#F2F2F2` | | Gauge · safe | `#6E9678` sage |
| Model segment · slate | `#495B6C` | | Gauge · warning | `#8C4820` rust |
| Folder segment · stone | `#716A56` | | Gauge · danger | `#AD0000` red |
| Git segment · forest | `#3F5147` | | Accent · ahead | `#96B4CD` sky |
| Base / background | `#26140A` | | Accent · behind | `#C98E47` amber |

---

## Customizing

Everything lives at the top of [`statusline.sh`](statusline.sh), commented.

**Thresholds** — the color flip points, all in one block:

```sh
CTX_WARN_PCT=70    # context + caps: sage -> rust at this % of the window/cap
CTX_DANGER_PCT=90  # ...             rust -> red  at this %
COST_WARN=5        # session cost:   sage -> rust at this many dollars
COST_DANGER=20     # ...             rust -> red  at this many dollars
```

**Palette** — the `# palette` block holds every color as an `R;G;B` triple. Swap them for your own brand; the semantic ramp is `SAGE → RUST → RED`.

**Effort flair** — edit the `case "$EFFORT"` block to change glyphs or colors per reasoning level.

> [!TIP]
> **Fast mode / thinking:** the documented payload doesn't expose a fast-mode field, so the `⚡` flag stays hidden rather than faking it (it lights up automatically if the field ever appears). To show **thinking on/off** instead, read `.thinking.enabled` near the `FAST=` line and append a glyph to `model_txt` the way the effort flair does.

---

## Settings precedence (worth knowing)

Claude Code merges settings in this order, later wins:

```
~/.claude/settings.json   →   <project>/.claude/settings.json   →   <project>/.claude/settings.local.json
```

So a **project** `.claude/settings.json` with its own `statusLine` (e.g. `ccusage`) will **override** your user-level bar in that repo. If a project's bar isn't the MountainLabs one, that's why — set `statusLine` in that project's `.claude/settings.local.json` (git-ignored, highest priority) to win locally without touching the shared file.

---

## Optional — the MountainLabs Ghostty theme

[`examples/ghostty.config`](examples/ghostty.config) is a full brand theme + eye-comfort layer for [Ghostty](https://ghostty.org), so Claude Code's *own* output (diffs, headings, tool results) matches the bar. Green stays green and red stays red so diffs and errors are never ambiguous. Copy it to `~/.config/ghostty/config` and reload with `Cmd+Shift+,`.

The statusline itself is terminal-agnostic — the theme is a nicety, not a requirement.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Boxes / `?` where icons should be | Your terminal font isn't a Nerd Font. Install one and set it as the terminal font. |
| 5h / weekly gauges missing | Expected on pay-as-you-go API billing — those fields only come with Pro/Max plans. |
| Cost looks off | Update the Claude Code CLI; the estimate tracks whatever pricing the installed version knows. |
| Bar is blank or errors | Run it by hand to see the error: `echo '{}' \| ~/.claude/statusline.sh` (needs `jq`). |
| A specific project shows a different bar | Settings precedence — see the note above. |

---

## Uninstall

```sh
# restore the settings.json the installer backed up
cp ~/.claude/settings.json.bak-statusline ~/.claude/settings.json

# and remove the script
rm ~/.claude/statusline.sh
```

---

## How it works

Claude Code invokes your `statusLine.command` on every render and pipes it a JSON object of session state on **stdin**. This script reads it with `jq`, formats two lines of ANSI-colored text, and prints them. The fields it uses: `model`, `workspace.current_dir`, `context_window.*`, `cost.*`, and `rate_limits.*`. Git state comes from `git` run against the workspace directory — which is what makes worktree and branch detection accurate regardless of what the payload includes.

See the [official statusline docs](https://code.claude.com/docs/en/statusline) for the full schema.

---

<div align="center">

Built with care by **[MountainLabs.ai](https://mountainlabs.ai)** · [MIT](LICENSE)

*Pairs well with a dark terminal and a strong cup of coffee.*

</div>
