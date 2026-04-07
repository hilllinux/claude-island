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
    case custom = "custom"

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .custom: return "Agent"
        }
    }

    var brandColor: Color {
        switch self {
        case .claude: return TerminalColors.amber
        case .gemini: return TerminalColors.blue
        case .custom: return TerminalColors.cyan
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "claude_logo"
        case .gemini: return "gemini_logo"
        case .custom: return "cpu"
        }
    }
}
