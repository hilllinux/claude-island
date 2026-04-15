//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Auto-installs agent hooks (Claude & Gemini) on app launch
//

import Foundation

struct HookInstaller {

    /// Install hook scripts and update settings for Claude, Gemini, and Qwen
    static func installIfNeeded() {
        installClaudeHooks()
        installGeminiHooks()
        installQwenHooks()
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

    /// Uninstall all hooks (Claude, Gemini, Qwen)
    static func uninstall() {
        uninstallClaude()
        uninstallGemini()
        uninstallQwen()
    }

    private static func uninstallClaude() {
        uninstallPythonHook(configDir: ".claude", scriptName: "claude-island-state.py")
    }

    private static func uninstallQwen() {
        uninstallPythonHook(configDir: ".qwen", scriptName: "qwen-island-state.py")
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
