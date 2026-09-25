# 02 — Technical spec

Read `tech-notes.md` §0 (findings that change the build), §8 (what they mean for the
build) and §9 (open questions for the M0 spike) first. They were researched read-only on
2026-09-25 on macOS 27; no shortcut was created, signed or run yet.

## What the research established

- **Metadata.** Every App Intent ships as JSON in `…/Metadata.appintents/extract.actionsdata`,
  readable without any permission. The Mac checked has 223 such files and 1,269 actions
  (942 discoverable in Shortcuts). Many of Apple's actions live in system frameworks under
  `/System/Library`, not in the apps. Third-party apps added only 23 actions.
- **Entity parameters are the core risk.** 666 of the 942 discoverable actions take an
  entity or array (a note, a reminder). Shortcuts rejects a plain string for an entity; it
  needs a variable, such as the output of a Find action. Only 129 actions on the Mac checked
  run in the background with primitive or enum parameters only.
- **The public route works in the wild.** Generate the plist → `shortcuts sign` → the user
  clicks "Add Shortcut" → `shortcuts run <UUID> --input-path … --output-path …`.
  sweetrb/apple-notes-mcp (133★) does this for Notes.
- **Per-tool onboarding cost:** one "Add Shortcut" click plus one foreground run set to
  "Always Allow", again after every wrapper upgrade. Otherwise background runs stall.
- **Signing needs the user's iCloud login, and Apple receives a copy for validation.** It
  does not need the $99 developer program.
- **Swift MCP SDK 0.12.1 fails the handshake with current Codex** (swift-sdk#287, open) and
  stops at spec 2025-11-25; the current spec is 2026-07-28.

## Architecture

```
Sources/
  IntentsIndex/     # scan apps AND /System/Library; parse metadata → [ActionSpec]
  ShortcutForge/    # build one wrapper .shortcut per action; sign via `shortcuts sign`
  Runner/           # `shortcuts run` with files, never inheriting stdin; timeouts
  MCPServer/        # stdio JSON-RPC MCP server (see "MCP server" below)
  Store/            # ~/Library/Application Support/intents-mcp: enabled tools, call log
  CLI/              # census, list, enable, disable, serve, log, doctor
Tests/
```

## Data model

```swift
struct ActionSpec: Codable {
  let id: String                    // stable: "<hostBundleID>.<intentIdentifier>"
  let app: AppRef                   // host app name, bundle ID, version, path, Team ID
  let title: String                 // resolved through .loctable / Localizable.strings
  let description: String?
  let parameters: [ParamSpec]       // name, title, kind, optional, enum values
  let outputType: String?
  let supportedModes: [String]      // background / foreground …
  let discoverable: Bool
  let destructive: Bool             // DeleteEntity protocol or name heuristics
  let tier: Tier                    // .simple / .needsEntity / .unsupported
}
enum ParamKind { case string, number, bool, date, enumeration([String]), entity(String), array, file, other }
```

- Map framework-hosted actions to their host app (Reminders, Calendar).
- **Default tool set (tier `.simple`):** discoverable, background-capable, primitive or enum
  parameters only, with an `outputType`. Destructive actions are off unless
  `--allow-destructive`.
- **Entity actions (tier `.needsEntity`):** generate `find_<entity>` tools from the entity's
  `queries`, and pass entities between calls by identifier. How to rehydrate an entity
  inside a wrapper is the key unknown (`tech-notes.md` §9, questions 1–4). Support it only
  if M0 proves a working encoding; otherwise list these actions as not yet supported.

## Runner

- `shortcuts run <UUID> --input-path <tmp.json> --output-path <tmp.out> --output-type public.plain-text`
- **Never let the child process inherit the MCP server's stdin** (it hangs the server).
  Redirect stdin from /dev/null.
- Timeout (default 30 s), check the exit code, and map "Couldn't find shortcut" to a clear
  "not added yet; run `intents-mcp enable …` and click Add Shortcut" error.
- **Verify by reading state back** where a read action exists (e.g. after "Create Note",
  find the note), following sweetrb. Report `verified` / `unverified` per call.

## MCP server

- stdio transport, one tool per enabled action; the input schema comes from `ParamSpec`;
  the description comes from the title, description and app name. Mark destructive tools
  with `destructiveHint`.
- **Codex compatibility is a launch requirement.** Either use the Swift SDK with the fix
  for swift-sdk#287 merged, or implement the small subset of MCP needed here (initialize,
  tools/list, tools/call, ping, notifications) directly as JSON-RPC over stdio, targeting
  spec 2026-07-28. Decide in M0 after testing the handshake with both Claude Code and Codex.
- Every call is appended to the local JSONL log: tool, time, duration, ok/error, verified.

## CLI

```
intents-mcp census [--json]                 # counts by tier; the launch number
intents-mcp list [--app <name>] [--tier simple|entity|all] [--json]
intents-mcp enable <id>... [--allow-destructive]
intents-mcp disable <id>...
intents-mcp serve
intents-mcp log [--last 50]
intents-mcp doctor     # macOS version, iCloud signed in, shortcuts CLI, wrappers present, "Always Allow" done
```

## Wording rules for the README and launch copy

Say "runs on your Mac" and "public APIs only". Do **not** say "nothing leaves your Mac":
signing a shortcut uses the user's iCloud account and Apple receives a copy for
validation. Say that plainly.

## Tests

- Metadata parsing on fixture JSON (structure only, no personal data).
- Tier classification on fixtures covering each parameter kind.
- ShortcutForge output is a well-formed plist for fixture actions.
- MCP server: initialize/tools/list/tools/call against a fake runner, with transcripts of
  both the Claude Code and Codex handshakes.
- Integration tests that need real shortcuts are tagged and skipped, not faked, when the
  wrapper isn't installed.
