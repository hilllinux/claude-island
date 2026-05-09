//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Auto-installs agent hooks (Claude & Gemini) on app launch
//

import Foundation

struct HookInstaller {

    /// Install hook scripts and update settings for Claude, Gemini, Qwen, and Codex
    static func installIfNeeded() {
        installClaudeHooks()
        installGeminiHooks()
        installQwenHooks()
        installCodexHooks()
    }

    // MARK: - Claude Support

    static func installClaudeHooks() {
        installPythonBasedHooks(
            agentName: "claude",
            configDir: ".claude",
            provider: "claude"
        )
    }

    // MARK: - Qwen Support

    static func installQwenHooks() {
        installPythonBasedHooks(
            agentName: "qwen",
            configDir: ".qwen",
            provider: "qwen"
        )
    }

    // MARK: - Codex Support

    static func installCodexHooks() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configDir = ".codex"
        let agentDir = homeDir.appendingPathComponent(configDir)
        let hooksDir = agentDir.appendingPathComponent("hooks")
        let scriptName = "codex-island-state.py"
        let pythonScript = hooksDir.appendingPathComponent(scriptName)
        let configPath = agentDir.appendingPathComponent("config.toml")

        // Only install if the agent directory exists
        if !FileManager.default.fileExists(atPath: agentDir.path) {
            return
        }

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(forResource: "claude-island-state", withExtension: "py") {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: pythonScript.path
            )
        }

        updateCodexConfig(at: configPath, scriptPath: "~/\(configDir)/hooks/\(scriptName)")
    }

    private static func updateCodexConfig(at configURL: URL, scriptPath: String) {
        let scriptName = scriptPath.components(separatedBy: "/").last ?? "codex-island-state.py"
        var contents = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let python = detectPython()
        let command = "\(python) \(scriptPath) --provider codex"

        contents = removeCodexHookEntries(from: contents, scriptName: scriptName)
        if !contents.contains("[hooks]") {
            contents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            contents += contents.isEmpty ? "[hooks]\n" : "\n\n[hooks]\n"
        }

        let existingEvents = codexHookEvents(in: contents)
        let hookConfigs = codexHookLines(command: command).filter { !existingEvents.contains($0.event) }
        let hookLines = hookConfigs.map { $0.line }
        contents = appendLines(hookLines, underSection: "hooks", in: contents)

        let stateLines = codexHookStateLines(
            configPath: configURL.path,
            events: hookConfigs.map { $0.event }
        )
        if !contents.contains("[hooks.state]") {
            contents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            contents += "\n\n[hooks.state]\n"
        }
        contents = appendLines(stateLines, underSection: "hooks.state", in: contents)

        try? contents.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func installPythonBasedHooks(agentName: String, configDir: String, provider: String) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let agentDir = homeDir.appendingPathComponent(configDir)
        let hooksDir = agentDir.appendingPathComponent("hooks")
        let scriptName = "\(agentName)-island-state.py"
        let pythonScript = hooksDir.appendingPathComponent(scriptName)
        let settings = agentDir.appendingPathComponent("settings.json")

        // Only install if the agent directory exists (meaning the agent is installed)
        // or if it's Claude (our primary target)
        if agentName != "claude" && !FileManager.default.fileExists(atPath: agentDir.path) {
            return
        }

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(forResource: "claude-island-state", withExtension: "py") {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        updatePythonHooksSettings(at: settings, scriptPath: "~/\(configDir)/hooks/\(scriptName)", provider: provider)
    }

    private static func updatePythonHooksSettings(at settingsURL: URL, scriptPath: String, provider: String) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let command = "\(python) \(scriptPath) --provider \(provider)"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains(scriptPath.components(separatedBy: "/").last ?? "claude-island-state.py")
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }

    // MARK: - Gemini Support

    static func installGeminiHooks() {
        let geminiDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
        let hooksDir = geminiDir.appendingPathComponent("hooks")
        let bridgeScript = hooksDir.appendingPathComponent("gemini-island-bridge.js")
        let settings = geminiDir.appendingPathComponent("settings.json")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        // Install our Node.js bridge script
        if let bundled = Bundle.main.url(forResource: "gemini-island-bridge", withExtension: "js") {
            try? FileManager.default.removeItem(at: bridgeScript)
            try? FileManager.default.copyItem(at: bundled, to: bridgeScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: bridgeScript.path
            )
        }

        updateGeminiSettings(at: settings)
    }

    private static func updateGeminiSettings(at settingsURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let bridgeCommand = "node ~/.gemini/hooks/gemini-island-bridge.js"
        
        func createHookConfig(_ eventName: String) -> [[String: Any]] {
            return [
                [
                    "matcher": "*",
                    "hooks": [
                        [
                            "name": "island-\(eventName.lowercased())",
                            "type": "command",
                            "command": "\(bridgeCommand) \(eventName)"
                        ]
                    ]
                ]
            ]
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let geminiEvents = ["SessionStart", "BeforeTool", "AfterTool", "SessionEnd"]

        for event in geminiEvents {
            let config = createHookConfig(event)
            
            if var existingEvent = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains("gemini-island-bridge.js")
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }

    // MARK: - Codex TOML Helpers

    private static func codexHookLines(command: String) -> [(event: String, line: String)] {
        [
            ("UserPromptSubmit", "UserPromptSubmit = [{ hooks = [{ type = \"command\", command = \"\(command)\" }] }]"),
            ("PreToolUse", "PreToolUse = [{ matcher = \"*\", hooks = [{ type = \"command\", command = \"\(command)\" }] }]"),
            ("PostToolUse", "PostToolUse = [{ matcher = \"*\", hooks = [{ type = \"command\", command = \"\(command)\" }] }]"),
            ("PermissionRequest", "PermissionRequest = [{ matcher = \"*\", hooks = [{ type = \"command\", command = \"\(command)\", timeout = 300 }] }]"),
            ("Stop", "Stop = [{ hooks = [{ type = \"command\", command = \"\(command)\" }] }]"),
            ("SessionStart", "SessionStart = [{ hooks = [{ type = \"command\", command = \"\(command)\" }] }]"),
        ]
    }

    private static func codexHookStateLines(configPath: String, events: [String]) -> [String] {
        let eventLabels = [
            "PermissionRequest": "permission_request",
            "PostToolUse": "post_tool_use",
            "PreToolUse": "pre_tool_use",
            "SessionStart": "session_start",
            "Stop": "stop",
            "UserPromptSubmit": "user_prompt_submit",
        ]

        return events.compactMap { eventLabels[$0] }.flatMap { event in
            [
                "[hooks.state.\"\(configPath):\(event):0:0\"]",
                "enabled = true",
            ]
        }
    }

    private static func codexHookEvents(in contents: String) -> Set<String> {
        let supportedEvents = Set(codexHookLines(command: "").map { $0.event })
        var events = Set<String>()
        var inHooksSection = false

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[hooks]" {
                inHooksSection = true
                continue
            }
            if inHooksSection && trimmed.hasPrefix("[") {
                break
            }
            guard inHooksSection,
                  let event = trimmed.components(separatedBy: "=").first?.trimmingCharacters(in: .whitespaces),
                  supportedEvents.contains(event) else {
                continue
            }
            events.insert(event)
        }

        return events
    }

    private static func removeCodexHookEntries(from contents: String, scriptName: String) -> String {
        let stateKeyPrefix = "[hooks.state."
        let supportedEvents = [
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "PermissionRequest",
            "Stop",
            "SessionStart",
        ]
        let unsupportedEvents = [
            "Notification",
            "SubagentStop",
            "SessionEnd",
            "PreCompact",
        ]
        let codexStateLabels = [
            ":permission_request:0:0",
            ":post_tool_use:0:0",
            ":pre_tool_use:0:0",
            ":session_start:0:0",
            ":stop:0:0",
            ":user_prompt_submit:0:0",
        ]

        var output: [String] = []
        var skippingStateBlock = false

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(stateKeyPrefix) {
                skippingStateBlock = codexStateLabels.contains { trimmed.contains($0) }
                if skippingStateBlock {
                    continue
                }
            } else if skippingStateBlock {
                if trimmed.hasPrefix("[") {
                    skippingStateBlock = false
                } else {
                    continue
                }
            }

            let removesHookLine = (supportedEvents + unsupportedEvents).contains { event in
                trimmed.hasPrefix("\(event) =") && trimmed.contains(scriptName)
            }
            if removesHookLine {
                continue
            }

            output.append(line)
        }

        return output.joined(separator: "\n")
    }

    private static func appendLines(_ lines: [String], underSection section: String, in contents: String) -> String {
        var output: [String] = []
        var inserted = false
        var inTargetSection = false

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "[\(section)]" {
                inTargetSection = true
                output.append(line)
                continue
            }

            if inTargetSection && trimmed.hasPrefix("[") {
                output.append(contentsOf: lines)
                output.append("")
                inserted = true
                inTargetSection = false
            }

            output.append(line)
        }

        if inTargetSection && !inserted {
            if output.last?.isEmpty == false {
                output.append("")
            }
            output.append(contentsOf: lines)
            inserted = true
        }

        if !inserted {
            if output.last?.isEmpty == false {
                output.append("")
            }
            output.append(contentsOf: lines)
        }

        return output.joined(separator: "\n")
    }

    // MARK: - Utils

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }

    /// Check if Claude hooks are currently installed
    static func isInstalled() -> Bool {
        isPythonHookInstalled(configDir: ".claude", scriptName: "claude-island-state.py")
    }

    /// Check if Qwen hooks are currently installed
    static func isQwenInstalled() -> Bool {
        isPythonHookInstalled(configDir: ".qwen", scriptName: "qwen-island-state.py")
    }

    /// Check if Codex hooks are currently installed
    static func isCodexInstalled() -> Bool {
        let agentDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        let config = agentDir.appendingPathComponent("config.toml")
        guard let contents = try? String(contentsOf: config, encoding: .utf8) else {
            return false
        }
        return contents.contains("codex-island-state.py")
    }

    private static func isPythonHookInstalled(configDir: String, scriptName: String) -> Bool {
        let agentDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(configDir)
        let settings = agentDir.appendingPathComponent("settings.json")

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains(scriptName) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    /// Check if Gemini hooks are currently installed
    static func isGeminiInstalled() -> Bool {
        let geminiDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
        let settings = geminiDir.appendingPathComponent("settings.json")

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains("gemini-island-bridge.js") {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    /// Uninstall all hooks (Claude, Gemini, Qwen, Codex)
    static func uninstall() {
        uninstallClaude()
        uninstallGemini()
        uninstallQwen()
        uninstallCodex()
    }

    private static func uninstallClaude() {
        uninstallPythonHook(configDir: ".claude", scriptName: "claude-island-state.py")
    }

    private static func uninstallQwen() {
        uninstallPythonHook(configDir: ".qwen", scriptName: "qwen-island-state.py")
    }

    private static func uninstallCodex() {
        let agentDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        let hooksDir = agentDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("codex-island-state.py")
        let config = agentDir.appendingPathComponent("config.toml")

        try? FileManager.default.removeItem(at: pythonScript)

        guard let contents = try? String(contentsOf: config, encoding: .utf8) else {
            return
        }
        let updated = removeCodexHookEntries(from: contents, scriptName: "codex-island-state.py")
        try? updated.write(to: config, atomically: true, encoding: .utf8)
    }

    private static func uninstallPythonHook(configDir: String, scriptName: String) {
        let agentDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(configDir)
        let hooksDir = agentDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent(scriptName)
        let settings = agentDir.appendingPathComponent("settings.json")

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains(scriptName)
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settings)
        }
    }

    private static func uninstallGemini() {
        let geminiDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
        let bridgeScript = geminiDir.appendingPathComponent("hooks/gemini-island-bridge.js")
        let settings = geminiDir.appendingPathComponent("settings.json")

        try? FileManager.default.removeItem(at: bridgeScript)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains("gemini-island-bridge.js")
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settings)
        }
    }
}
