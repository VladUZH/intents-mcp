# STATUS — intents-mcp

Append-only log. After every task: what was done, how it was verified (command + result),
what is blocked and why, and decisions made where the docs were silent.

## Current milestone

M0 — feasibility spike (in progress). GATE passed 2026-09-25; live tests running.

## Log

- 2026-09-25 — Project folder prepared: CLAUDE.md, docs/01–05, tech-notes, evidence,
  one-pager. No code yet.

- 2026-09-25 — M0 started. Read CLAUDE.md, docs/01–05, tech-notes, evidence.
- 2026-09-25 — M0: picked test actions from real metadata (`Spike/`, python dump of
  `extract.actionsdata`):
  - simple 1: Reminders `TTRCreateReminderAppIntent` (title:String, dueDate?:DateComponents
    → ReminderEntity), hosted in `RemindersAppIntents.framework`, bundle
    `com.apple.RemindersAppIntents`; wrapper uses `com.apple.reminders` (to test §9 q3).
  - simple 2: Notes `CreateNoteLinkAction` (name?, contents?:AttributedString,
    interpretAsMarkdown:Bool → NoteEntity), `com.apple.Notes`.
  - entity: Notes `AppendToNoteLinkAction`, two ways: chained Find Notes (name is X,
    limit 1) and entity fed straight from a JSON id string (§9 q4).
  - third party: CotEditor 7.0.7 `CreateDocumentIntent` (content:String; opens app; no
    output; team HT3Z3A72WZ) and MacWhisper 13.23.1 `TranscribeAudioIntent`
    (audioFile:file → String, the only 3rd-party action with output; team 8Q7TMPA46J).
  - Calendar `CreateEventIntent` is NOT simple: `calendar` is a required CalendarEntity.
- 2026-09-25 — M0: `Spike/forge.py` builds 7 unsigned wrappers (binary plist) into
  `Spike/out/` (git-ignored): reminders-add-A (detect.dictionary+getvalueforkey),
  reminders-add-B (compact aggrandizement input), notes-create, notes-append-find,
  notes-append-id, coteditor-create, macwhisper-transcribe.
  Verified: `python3 Spike/forge.py && plutil -lint Spike/out/*.shortcut` → 7× OK.
  `Spike/run.py` runs by UUID with stdin=/dev/null, timeout, timing (not run yet: GATE).
- 2026-09-25 — M0: MCP handshake test (`Spike/mcp`: `hand` = hand-written JSON-RPC,
  `sdk` = swift-sdk 0.12.1; both one `echo` tool; `trace.sh` records raw frames).
  - Claude Code 2.1.282 (`claude -p … --strict-mcp-config --mcp-config …`): **both pass**
    initialize + tools/list + tools/call. Claude Code first sends `server/discover`
    (spec 2026-07-28), gets -32601, falls back to `initialize` 2025-11-25. When
    `structuredContent` is present Claude Code shows the model that, not the text.
  - Codex 0.146.0 (installed): both pass initialize + tools/list (it sends no
    `experimental`); no tool call — configured model `gpt-6-astra` needs a newer CLI.
  - Codex 0.157.0 (latest, via `npx -y @openai/codex@latest`, global install untouched):
    sends `capabilities.experimental: {"codex/auth-change": {}}`. **sdk fails initialize**
    (-32603 "The data couldn't be read because it isn't in the correct format.") =
    swift-sdk#287 reproduced. **hand passes** initialize (2025-06-18) + tools/list.
    tools/call not reached: Codex account usage limit ("try again at 3:41 PM").
  - Blocked: Codex tools/call against `hand` — re-run after the usage limit resets.
- 2026-09-25 — **GATE passed:** user OK'd signing/importing/running test shortcuts and is
  present. Live results so far (`Spike/run.py`, stdin=/dev/null):
  - **Signing (§9 q1):** `shortcuts sign --mode people-who-know-me` → exit 0, `AEA1`, ~0.3 s
    each, for all 7 + 3 later wrappers. Imports on this Mac via `open <file>` → "Add
    Shortcut" sheet ("Shared", "Please review this shortcut…"); no Private Sharing issue.
    (Offline / signed-out not tested.)
  - **Notes Create Note via App Intent keys** (`com.apple.Notes.CreateNoteLinkAction`,
    `name`, `contents`): 4 runs, exit 0, note created each time, cold 6.29 s, warm
    0.55–1.05 s. `name` arrived (note title); **`contents` silently dropped** ("No
    additional text"). No output (see below). The first run showed a prompt the user
    didn't answer; later runs didn't prompt.
  - **Input plumbing (§9 q6):** `imcp-spike-echo` (no app) returns
    `A=héllo wörld ✓|B=héllo wörld ✓`: both detect.dictionary+getvalueforkey+gettext (A)
    and the compact aggrandizement form (B) work, non-ASCII intact, 0.26–0.28 s, no prompt.
  - **Legacy serialization works:** `com.apple.mobilenotes.SharingExtension` with
    `WFCreateNoteInput` (sweetrb's form) creates the note with title + body. So some App
    Intents are served by a legacy action whose plist keys ≠ metadata `parameters[].name`,
    and a wrong key is **silently ignored with exit 0** (§9 q8). The metadata has no hint
    of the mapping.
  - **Consent (§9 q5):** each wrapper that writes data prompts once: "Allow “<shortcut>” to
    save 1 dictionary in a note?" with Don't Allow / Allow Once / Always Allow. The preview
    shows the data's *source* (the input JSON), not what is written. Unanswered, `shortcuts
    run` blocks (40 s timeouts), and it can also return exit 0 before the prompt is
    answered. After Always Allow: 0.40–0.41 s, no prompt.
  - **Output (§9 q7):** entity result → Stop and Output as plain text gave **no output**
    file. Result → Get Text → Stop and Output returns the note's text (title + body).
    `OutputName` doesn't matter (Result/Note/Notes all resolve); `OutputUUID` does.
    `WFWorkflowHasOutputAction: true` is now set (sweetrb sets it; v1 lacked it; effect
    not isolated).
  - **Re-import (§9 q5):** opening an updated file with the same name → "Add Shortcut" →
    "Replace" still **creates a new shortcut with a new UUID**; the older one was renamed
    "… 2"; the name now appears twice. **Always Allow does not carry over** (prompt came
    back, 13.8 s run). The CLI has no delete. The product must re-resolve UUIDs after each
    import, run by UUID, and tell the user to delete stale copies.

## Decisions

- 2026-09-25 — **MCP: hand-written JSON-RPC over stdio, not swift-sdk 0.12.1.** Evidence
  above: SDK fails `initialize` with current Codex (#287); hand-written works with both
  clients. It echoes the client's protocolVersion if supported (2025-11-25, 2025-06-18,
  2025-03-26, 2024-11-05) and answers `server/discover` with -32601 so dual-era clients
  fall back. Base it on Limatum's `LimatumMCP.swift` + `JSONValue`. Revisit native
  2026-07-28 (`server/discover`) support in "Later".
- 2026-09-25 — M0 spike code is Python (plistlib) for wrappers + a throwaway SwiftPM
  package for the handshake; kept in `Spike/` for reproducibility, not product code.
- 2026-09-25 — Wrappers are binary plists named `imcp-spike-<key>.unsigned.shortcut`
  (signer needs `.shortcut`; sometimes rejects XML — tech-notes §3.4).

## Human steps waiting (GATE)

- 2026-09-25 — **M0 live half (tech-notes §9 q1–q9).** Needs the user's OK to sign
  (`shortcuts sign --mode people-who-know-me` first; `anyone` only if needed), import
  (user clicks "Add Shortcut" per wrapper), run each once in Shortcuts.app with
  "Always Allow", then run via `Spike/run.py`. Test data it creates: 1–3 reminders
  titled "imcp-spike …", 1 note "imcp-spike note", 1 untitled CotEditor document, one
  MacWhisper transcription of a short test audio file. All removable afterwards.
  Also needs: confirmation the Mac is signed into iCloud (couldn't read it without
  touching account data).

## Later
