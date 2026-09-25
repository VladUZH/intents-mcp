# Privacy

intents-mcp runs on your Mac. It has no servers, accounts, analytics or telemetry.

**What it reads.** App Intents metadata files inside installed apps and macOS
(`Metadata.appintents/extract.actionsdata`); your Shortcuts library's names and IDs (with
`shortcuts list`); and, to confirm a result, the newest reminder or calendar event, through a
read-back shortcut you added yourself.

**What it stores**, in `~/Library/Application Support/intents-mcp`: the tools you enabled, the
wrapper shortcuts it built, and a call log with tool name, time, duration, success and
whether the result was verified. Tool arguments and results are not written to the log.

**What leaves your Mac.**
- *Shortcut signing.* `shortcuts sign` uses your iCloud account, and Apple receives a copy of
  each wrapper for validation. A wrapper describes an action and its inputs; it holds no
  personal data.
- *Your agent.* Tool results go to the MCP client that called the tool (Claude Code, Codex,
  Claude Desktop…). That client may send them to its model provider, under that provider's
  terms.
- *Nothing else.* intents-mcp opens no network connections of its own.

**Removing it.** `intents-mcp disable <tool>` stops exposing a tool. Delete its
"intents-mcp …" shortcut in the Shortcuts app, and delete the folder above to remove all
local data.
