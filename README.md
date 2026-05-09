<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Agent Island</h3>
  <p align="center">
    A macOS menu bar app that brings Dynamic Island-style notifications to Claude Code, Gemini CLI, Qwen Code, and Codex sessions.
    <br />
    <br />
    <a href="https://github.com/farouqaldori/claude-island/releases/latest" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/github/v/release/farouqaldori/claude-island?style=rounded&color=white&labelColor=000000&label=release" alt="Release Version" />
    </a>
    <a href="#" target="_blank" rel="noopener noreferrer">
      <img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/farouqaldori/claude-island/total?style=rounded&color=white&labelColor=000000">
    </a>
  </p>
</div>

## Features

- **Notch UI** — Animated overlay that expands from the MacBook notch
- **Multi-Agent Support** — Support for Claude Code, Gemini CLI, Qwen Code, and Codex
- **Live Session Monitoring** — Track multiple agent sessions in real-time
- **Permission Approvals** — Approve or deny tool executions directly from the notch
- **Chat History** — View full conversation history with markdown rendering
- **Auto-Setup** — Hooks install automatically on first launch

## Requirements

- macOS 15.6+
- Claude Code, Gemini CLI, Qwen Code, or Codex

## Install

Download the latest release or build from source:

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build
```

## How It Works

Agent Island installs hooks into agent configuration directories (e.g., `~/.claude/hooks/`) that communicate session state via a Unix socket. The app listens for events and displays them in the notch overlay.

When an agent needs permission to run a tool, the notch expands with approve/deny buttons—no need to switch to the terminal.

### Codex Hooks

Codex integration uses `~/.codex/config.toml` and installs `~/.codex/hooks/codex-island-state.py`. Agent Island only registers Codex-supported hook events:

- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `PermissionRequest`
- `Stop`
- `SessionStart`

The installer also writes Codex hook review state with `enabled = true` under `[hooks.state]`, which matches current Codex hook approval behavior and avoids repeated "hooks need review" prompts. Unsupported Claude-style events such as `Notification`, `SessionEnd`, and `PreCompact` are not registered for Codex.

## Analytics

Agent Island uses Mixpanel to collect anonymous usage data:

- **App Launched** — App version, build number, macOS version
- **Session Started** — When a new agent session is detected

No personal data or conversation content is collected.

Hook events are sent over a same-user Unix socket. Non-approval events use a short socket timeout and Codex tool lifecycle updates avoid sending full tool input payloads unless an approval decision is required.

## License

Apache 2.0
