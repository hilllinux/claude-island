#!/usr/bin/env node

/**
 * Agent Island - Gemini CLI Bridge
 * 
 * This script acts as a middleware between Gemini CLI hooks and the Agent Island
 * macOS app. It communicates via the /tmp/claude-island.sock Unix socket.
 */

const fs = require('fs');
const net = require('net');

async function main() {
    // 1. Read input from Gemini CLI (stdin)
    let input = {};
    try {
        const rawInput = fs.readFileSync(0, 'utf8');
        if (rawInput) {
            input = JSON.parse(rawInput);
        }
    } catch (e) {
        // Fallback for non-JSON input or empty stdin
    }

    // 2. Determine Event and Status
    // Gemini events: SessionStart, BeforeAgent, BeforeTool, AfterTool, SessionEnd, etc.
    const geminiEvent = process.argv[2] || 'Notification';
    const socketPath = '/tmp/claude-island.sock';

    const eventMap = {
        'SessionStart': { event: 'SessionStart', status: 'starting' },
        'BeforeTool': { event: 'PermissionRequest', status: 'waiting_for_approval' },
        'AfterTool': { event: 'PostToolUse', status: 'idle' },
        'SessionEnd': { event: 'SessionEnd', status: 'ended' },
        'Default': { event: 'Notification', status: 'processing' }
    };

    const mapped = eventMap[geminiEvent] || eventMap['Default'];

    // 3. Construct Payload for Agent Island
    const payload = {
        provider: 'gemini',
        session_id: input.session_id || process.env.GEMINI_SESSION_ID || 'gemini-session',
        cwd: process.cwd(),
        event: mapped.event,
        status: mapped.status,
        pid: process.ppid, // Parent process is the CLI
        tool: input.tool_name,
        tool_input: input.tool_input,
        tool_use_id: input.tool_use_id || `gemini-${Date.now()}`,
        message: input.prompt_response || input.systemMessage
    };

    // 4. Send to Agent Island Socket
    const client = net.createConnection(socketPath, () => {
        client.write(JSON.stringify(payload));
        
        // For events that don't require a response, we end immediately
        if (payload.event !== 'PermissionRequest') {
            client.end();
            process.exit(0);
        }
    });

    // 5. Handle Response (specifically for PermissionRequest)
    client.on('data', (data) => {
        try {
            const response = JSON.parse(data.toString());
            // Return structured decision to Gemini CLI (stdout)
            process.stdout.write(JSON.stringify({
                decision: response.decision || 'allow',
                reason: response.reason,
                systemMessage: response.decision === 'deny' ? '🔒 Blocked by Agent Island' : null
            }));
        } catch (e) {
            process.stdout.write(JSON.stringify({ decision: 'allow' }));
        }
        client.end();
        process.exit(0);
    });

    // Handle connection errors (e.g. App not running)
    client.on('error', (err) => {
        // Default to 'allow' if the app is not reachable to avoid blocking the user
        if (payload.event === 'PermissionRequest') {
            process.stdout.write(JSON.stringify({ decision: 'allow' }));
        }
        process.exit(0);
    });

    // Timeout safety
    setTimeout(() => {
        if (payload.event === 'PermissionRequest') {
            process.stdout.write(JSON.stringify({ decision: 'allow' }));
        }
        process.exit(0);
    }, 5000);
}

main().catch(err => {
    // Never crash the CLI
    process.exit(0);
});
