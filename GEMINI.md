# Agent Island - Gemini Context

Agent Island (formerly Claude Island) is a macOS menu bar application that brings a "Dynamic Island" style notification and control interface to AI CLI agents like **Claude Code** and **Gemini CLI**. It provides a sleek, animated notch overlay that allows users to monitor active agent sessions and handle tool execution permissions without leaving their current context.

## Project Overview

- **Core Purpose:** Enhance the AI Agent CLI experience with real-time notifications and interactive permission management via a MacBook-style notch UI.
- **Multi-Agent Support:** Supports Claude (Orange/Crab branding) and Gemini (Blue/Star branding).
- **Main Technologies:** Swift, SwiftUI, AppKit, Unix Domain Sockets, Python (for hooks).
- **Target Platform:** macOS 15.6+ (designed for MacBook notch).

## Architecture & Data Flow

### 1. Agent Hooks & IPC
The app monitors agents via a **Unix Domain Socket** at `/tmp/claude-island.sock`. 
- **Claude:** Automatically installs a Python hook script (`claude-island-state.py`) into `~/.claude/hooks/`.
- **Gemini / Others:** Can send JSON-encoded `HookEvent` objects to the socket. The event should include a `"provider": "gemini"` field for proper branding.
- **Permissions:** For `PermissionRequest`, the socket remains open until the app sends back a `HookResponse` (`allow` or `deny`).

### 2. Multi-Provider Modeling
- **`AgentProvider`:** Enum defining supported agents (`.claude`, `.gemini`, `.custom`) with their respective brand colors and icons.
- **`SessionState`:** Tracks the provider for each session to ensure correct UI rendering.

### 3. App Services
- **`HookSocketServer`:** Manages the Unix socket, parsing incoming events and routing responses.
- **`ClaudeSessionMonitor`:** Bridges socket events to the application's state management.
- **`SessionStore`:** Centralized actor-based store maintaining state for all active and pending sessions.

### 4. UI Layer (Notch UI)
- **`NotchView`:** The primary SwiftUI view that renders the expanded interface.
- **`AgentInstancesView`:** Lists active sessions with provider-specific icons and status indicators.
- **`AgentIcon`:** A dynamic pixel-art component that renders as a Crab for Claude or a Star for Gemini.
- **`ChatView`:** A full chat history interface with markdown support and provider-specific styling.

## Gemini Support Implementation

To send events from a Gemini-based CLI to Agent Island:
1. Connect to the Unix socket at `/tmp/claude-island.sock`.
2. Send a JSON object matching the `HookEvent` structure:
   ```json
   {
     "session_id": "unique-session-id",
     "cwd": "/path/to/project",
     "provider": "gemini",
     "event": "SessionStart",
     "status": "starting"
   }
   ```
3. For permission requests, ensure the `tool_use_id` is provided and wait for the response on the same socket connection.

## Building and Running

### Build Commands
To build the application from the command line:
```bash
xcodebuild -scheme ClaudeIsland -configuration Release build
```

## Development Conventions

- **Branding:** Always use `session.provider.brandColor` and `AgentIcon` instead of hardcoded colors or icons.
- **Concurrency:** Extensive use of Swift Concurrency (`Task`, `@MainActor`).
- **Socket Safety:** Non-blocking I/O using GCD `DispatchSourceRead`.

## Key Files
- `AgentProvider.swift`: Provider definitions and branding.
- `AgentInstancesView.swift`: Main session list (replaces ClaudeInstancesView).
- `NotchHeaderView.swift`: Contains `AgentIcon` and other header components.
- `HookSocketServer.swift`: Socket server implementation.
- `SessionStore.swift`: Source of truth for session data.
- `ChatView.swift`: Multi-agent chat interface.
