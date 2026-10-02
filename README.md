<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Notch Talk</h3>
  <p align="center">
    A macOS menu bar app that brings Dynamic Island-style notifications to Claude Code CLI sessions.
  </p>
</div>

## Features

- **Notch UI** — Animated overlay that expands from the MacBook notch
- **Live Session Monitoring** — Track multiple Claude Code sessions in real-time
- **Permission Approvals** — Approve or deny tool executions directly from the notch
- **Send Messages** — Type to Claude Code right from the notch (Terminal.app, iTerm2 or tmux)
- **Chat History** — View full conversation history with markdown rendering
- **Auto-Setup** — Hooks install automatically on first launch

## Requirements

- macOS 15.6+
- Claude Code CLI

## Install

Download the latest release or build from source:

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build
```

## How It Works

Notch Talk installs hooks into `~/.claude/hooks/` that communicate session state via a Unix socket. The app listens for events and displays them in the notch overlay.

When Claude needs permission to run a tool, the notch expands with approve/deny buttons—no need to switch to the terminal.

## Analytics

None. This fork does not collect or send any usage data.

## License

Apache 2.0, see `LICENSE.md` and `NOTICE`.
