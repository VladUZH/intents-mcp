# Privacy

intents-mcp runs on your Mac. It has no servers, accounts, analytics or telemetry.

**What it reads.**
- App Intents metadata files inside installed apps and macOS (`Metadata.appintents/extract.actionsdata`).
- Your Shortcuts library's names and IDs (with `shortcuts list`).
- To confirm a result: through a read-back shortcut you added yourself, the newest reminder or
  calendar event **with the title the tool just used**, including its due or start date and when
  it was created. If that item turns out to be a different or older one, its details are not
  shown to the agent.
- Only if the app running your agent (Terminal, VS Code, Claude Desktop…) already has full
  access to Reminders or Calendar: the same check is done with Apple's EventKit instead. That
  loads your reminders (completed ones included) or your events from a year back to 11 years
  ahead into the intents-mcp process, keeps only items with the title just used, and returns
  only their due or start time. intents-mcp never asks for this access itself.

**What it stores**, in `~/Library/Application Support/intents-mcp` (or `$INTENTS_MCP_HOME`):
- the tools you enabled (`tools.json`);
- for each tool, the unsigned wrapper it built and, for tools generated from metadata, the
  action's description (`action.json`). The signed wrapper is deleted as soon as intents-mcp
  sees the shortcut in your library (after `enable`, or on the next `enable`, `doctor`, `serve`
  or call of that tool), because it carries your Apple Account's signing identity (see below);
- a call log: tool name, time, duration, success, whether the result was verified, and who
  called (e.g. `mcp:claude-code`), written when a call starts and when it ends. Tool
  arguments and results are never written to the log.

While a tool runs, its arguments and output sit briefly in private temporary files (readable
only by you), deleted when the call ends, and on Ctrl-C or when the client quits.

**What leaves your Mac.**
- *Shortcut signing.* `shortcuts sign` uses your iCloud account, and Apple receives a copy of
  each wrapper for validation. The wrapper describes an action and its inputs. The signed file
  also contains your Apple Account's signing identity: an account identifier and hashed email
  address and phone number, which Apple's "people who know me" signing adds. Don't share
  signed `.shortcut` files.
- *Your Shortcuts library.* The shortcuts you add (tools and read-back helpers) are stored in
  your Shortcuts library, which syncs to your other devices through iCloud.
- *Your agent.* Tool results go to the MCP client that called the tool (Claude Code, Codex,
  Claude Desktop…). That client may send them to its model provider, under that provider's
  terms.
- *Nothing else.* intents-mcp opens no network connections of its own.

**Removing it.** `intents-mcp disable <tool>` stops exposing a tool and lists the shortcuts to
delete in the Shortcuts app (the CLI can't delete shortcuts). Delete the folder above to remove
all local data.
