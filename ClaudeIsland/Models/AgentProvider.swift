//
//  AgentProvider.swift
//  ClaudeIsland
//
//  Supported AI agent providers
//

import SwiftUI

enum AgentProvider: String, Codable, Sendable {
    case claude = "claude"
    case gemini = "gemini"
    case qwen = "qwen"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .qwen: return "Qwen"
        case .custom: return "Agent"
        }
    }

    var brandColor: Color {
        switch self {
        case .claude: return TerminalColors.amber
        case .gemini: return TerminalColors.blue
        case .qwen: return TerminalColors.purple
        case .custom: return TerminalColors.cyan
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "claude_logo"
        case .gemini: return "gemini_logo"
        case .qwen: return "qwen_logo"
        case .custom: return "cpu"
        }
    }

    var configDirectoryName: String {
        switch self {
        case .claude: return ".claude"
        case .gemini: return ".gemini"
        case .qwen: return ".qwen"
        case .custom: return ".agent"
        }
    }
}
