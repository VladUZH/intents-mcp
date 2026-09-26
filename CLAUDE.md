# intents-mcp — instructions for Claude Code

You are building **intents-mcp**, launch bet 3 of 3. Read this file, then `docs/` in
numeric order, then `docs/tech-notes.md` (§0, §8 and §9 change the build) and
`docs/evidence-adoption-check.md`.
`docs/one-pager.html` is the visual pitch.

## The one-paragraph product

`intents-mcp` is a Swift command-line tool for macOS. It finds the App Intents that Mac
apps and system frameworks expose (1,269 actions on the Mac checked, 942 usable in
Shortcuts), lets the user choose which ones an
agent may use, wraps each chosen action in a signed Shortcut (the public route; the user
clicks "Add Shortcut" once per action), and serves them as MCP tools over stdio to
Claude Code, Codex, Claude Desktop or any MCP client. It runs on the user's Mac.
The goal is **popularity** (GitHub stars, Homebrew installs), not revenue.

## Non-negotiables

1. **Public APIs only.** No private frameworks, no private XPC services, no entitlements
   that require disabling SIP or AMFI. (The existing bridge, action-relay, needs SIP off;
   not doing that is our point.)
2. **The user chooses every tool.** Nothing is exposed until the user enables it. Actions
   whose names or descriptions suggest deleting, sending, purchasing or sharing are
   marked and need an explicit extra flag to enable.
3. **Local, and honest about it.** No network of our own except MCP over stdio to the
   local client. No telemetry. Signing a shortcut uses the user's iCloud account and Apple
   receives a copy for validation: say so, and never claim "nothing leaves your Mac".
4. **Every call is logged locally** (tool, time, success, duration, verified; no personal
   content by default) so the user can see what agents did. Verify results by reading
   state back where a read action exists.
5. **No invented numbers.** The "N agent tools on your Mac" figure comes from a real scan.
6. **Feasibility first.** M0 is a spike that proves the whole path (index → shortcut →
   sign → add → run → result) on real intents before any product code.
7. **Weekend scope first** (M0–M3 in `docs/03-work-plan.md`); the rest goes to "Later".

## How to work

- Milestone by milestone (`docs/03-work-plan.md`), with acceptance checks run for real
  and recorded (command + result) in `STATUS.md`. Keep `STATUS.md` current; append only.
- **GATE (human):** creating, signing, importing or running any shortcut on this Mac
  (ask first; the user must be signed into iCloud and present to click "Add Shortcut"
  and "Always Allow"), anything needing a developer account (signing a distributable
  binary, notarization), making the repo public, Homebrew tap publishing, MCP Registry
  submission, posting anywhere.
- Docs silent → choose the simpler, safer, more local option; log it under "Decisions".
- Stack: Swift 6, SwiftPM, macOS 26+ (check the lowest macOS version the path works on in
  M0). MCP: the official Swift SDK 0.12.1 fails the handshake with current Codex
  (swift-sdk#287) and stops at spec 2025-11-25; M0 decides between a fixed SDK and a small
  hand-written JSON-RPC server. It must work with both Claude Code and Codex.
- Never let a spawned `shortcuts` process inherit the MCP server's stdin; it hangs.
- Commit small, conventional messages.
- The founder's earlier project at `/Users/vlpetrov/Documents/Programming/limatum` has
  working Swift code for Apple Events, the Accessibility tree, read-back verification, a
  policy dial and an append-only ledger. Reuse code from it where it helps (same author);
  don't copy its scope.

## Commands (target state)

```
swift build
swift test
swift run intents-mcp list [--app Notes] [--json]
swift run intents-mcp census            # counts tools on this Mac; the launch number
swift run intents-mcp enable reminders.add calendar.create-event
swift run intents-mcp serve             # MCP over stdio
claude mcp add --scope user mac -- intents-mcp serve
```

## What "done" looks like for the launch

`brew install` (from the project tap) and one `enable` give Claude Code and Codex working
Mac actions (at least the simple tier: Reminders, Calendar and similar), with verified
results returned. `census` produces the
real launch number. `docs/04-launch.md` is filled in, waiting for the human to post.
