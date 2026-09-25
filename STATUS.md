# STATUS — intents-mcp

Append-only log. After every task: what was done, how it was verified (command + result),
what is blocked and why, and decisions made where the docs were silent.

## Current milestone

M1 — index, census, list, doctor (in progress). M0: **GO**, signed off by the human 2026-09-25.

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
  - (Codex tools/call against `hand`: done later, see below.)
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
- 2026-09-25 — M0 live, part 2:
  - **Third-party (go criterion): PASS.** CotEditor `CreateDocumentIntent` (content:String):
    prompt "Allow “imcp-spike-coteditor-create” to share 1 dictionary with “CotEditor”?",
    then the document opened with both lines; wrapper output `COTEDITOR_OK`, exit 0, 11.06 s
    incl. the prompt. MacWhisper `TranscribeAudioIntent` (audio file as the Shortcut
    Input via `--input-path`): prompt "…to share 1 media item with “MacWhisper”?", output
    `This is the Intense MCP Spike, testing transcription.` (source audio: `say` "intents
    M C P spike"), exit 0, 87.44 s incl. the prompt. App Intent keys worked for both
    (no legacy mapping).
  - **Reminders (§9 q3): import rejected.** `com.apple.reminders.TTRCreateReminderAppIntent`
    (+ descriptor com.apple.reminders / 0000000000; exact ID and keys from shortcutkit's
    catalog) → "Can't Import Shortcut. This shortcut can't be imported because it contains
    features not supported on this device." Bisected: 3 probes (with/without
    `ActionRequiresAppInstallation`, with/without dueDate, title only) all rejected, so
    the action ID itself is unknown to Shortcuts on this Mac. Intent is hosted in
    `RemindersAppIntents.framework` (bundle `com.apple.RemindersAppIntents`); nothing on
    disk links it to Reminders.app. The right Mac ID is still open. Good news: an unknown
    ID fails **loudly at import**, not silently at run.
  - **INCIDENT — entity via Find touched a real user note.** `notes-append-find` (Find
    Notes where Name *is* "imcp-spike legacy title", limit 1 → AppendToNoteLinkAction)
    matched an unrelated personal note; exit 0, 16.15 s. The run's output was that note's
    text. Visible content unchanged (the `text` value was apparently dropped, like
    `contents`), but the note's modified time became 15:45 (the run), and a trailing
    space or newline may have been added. The filter (Operator 4 on "Name") was evidently
    ignored, leaving "all notes, limit 1". Entity tests stopped. `notes-append-id` NOT run.
- 2026-09-25 — **Handshake go criterion: PASS.** Codex 0.157.0 (`npx -y
  @openai/codex@latest exec …`) → hand server: initialize (with `experimental`
  object) → tools/list → tools/call `echo` → model replied `echo: ping-hand`. Together with
  Claude Code 2.1.282 above, the hand-written server works with both clients.
- 2026-09-25 — **Reminders/Calendar ground truth.** The user built "Add New Reminder" + "Add
  New Event" in Shortcuts.app and exported the file (`~/Downloads/imcp-ref.shortcut`,
  iCloud-notarized). `Spike/unwrap.sh` (aea decrypt with the key from the auth data or
  the leaf cert + `aa extract`; built-in tools only) shows the Mac uses **built-in
  actions** `is.workflow.actions.addnewreminder` / `addnewevent` (keys
  `WFCalendarItemTitle`, `WFCalendarItemNotes`), not the App Intents. Other keys from
  shortcutkit `data/builtin-actions.json`.
- 2026-09-25 — **Simple action 2 (go criterion): PASS.** `imcp-spike-reminders-builtin`
  (title, notes, alert `WFAlertCustomTime` from text "tomorrow at 10:00"): cold 5.78 s,
  warm 0.31 s, exit 0, output `imcp-spike reminder`. `imcp-spike-calendar-builtin`
  (title, start, end as text, ShowWhenRun off): 1.47 s / warm 0.32 s, output
  `imcp-spike event`. The user confirmed in Reminders/Calendar: titles, notes and times
  are exact (10:00, 10:30; 12:00–12:30, 13:00–13:15). No blocking prompt on these runs.
- 2026-09-25 — **Wrong key (§9 q8):** `{"titel": …}` on the Reminders wrapper → exit 1,
  stderr `Error: No title was provided. Please provide a title for this reminder.`
  (a required field fails loudly; an optional wrong key is dropped silently: Notes `contents`).
- 2026-09-25 — **M0 summary against the accept criteria:**
  - 2 simple actions end to end with parameters and output: Notes Create Note (legacy
    form), Reminders Add, and also Calendar Add: **pass**.
  - Third-party action with parameters and output: CotEditor (param), MacWhisper
    (file → text): **pass**.
  - Handshake with Claude Code and Codex: hand-written server, **pass**.
  - Entities: **"not yet"**; v1 ships the simple tier only.
  - Lowest macOS version: only macOS 27.0 (26A428) was tested; nothing older is available here.
  - Not tested: signing offline or signed out (§9 q1), cert expiry (§9 q10), the
    `openAppWhenRun` behaviour beyond CotEditor opening its window (§9 q9), and runs spawned
    by an MCP server under each client (§9 q5; do this in M3).
- 2026-09-25 — Human: M0 **go** signed off; deleted `imcp-spike-notes-append-find` and
  `imcp-spike-notes-append-id` (checked: neither is in `shortcuts list` any more).
- 2026-09-25 — M1 started.

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
- 2026-09-25 — **Entities are "not yet" for v1: the simple tier only.** Evidence: the
  Find-chain filter silently degraded to an arbitrary note (incident above). Rule for any
  later entity work: never act on a Find result without checking count == 1 AND reading
  back the matched identity before the act step. Also, no personal content in output by
  default: the wrapper must not echo whole entities.
- 2026-09-25 — Wrappers must pass a result through Get Text before Stop and Output
  (entity → no output otherwise).
- 2026-09-25 — Param keys can't be trusted from metadata alone (Notes Create Note:
  `contents` ignored, legacy `WFCreateNoteInput` works; exit 0 either way). So `enable`
  needs a per-action verified key map, or a read-back check that fails loudly.
- 2026-09-25 — **The M1 census must not equate "in metadata" with "usable".** Import-time
  checks reject some App Intents on the Mac (Reminders `TTRCreateReminderAppIntent`),
  while the Mac's own Reminders/Calendar actions are built-ins that the metadata scan
  doesn't see. Plan for M1: census counts from metadata, labelled as such
  ("declared"); a curated, verified "simple tier" that mixes App Intents that work
  (Notes, CotEditor, MacWhisper) with built-ins (Reminders, Calendar), each with a known
  key map verified live. The launch number must say which of the two it is (rule 5: no
  invented numbers). The "942 usable in Shortcuts" figure in the docs is unverified.
- 2026-09-25 — Wrapper recipe (M2): detect.dictionary → getvalueforkey → gettext per
  key → action (strings/dates as token strings) → gettext → output;
  `WFWorkflowHasOutputAction: true`; binary plist; `people-who-know-me` signing; run by
  UUID with stdin=/dev/null; resolve the UUID again after every import.

## Human steps waiting (GATE)
- 2026-09-25 — **M0 go/pivot sign-off** (work plan: go/pivot gate before M1).
- 2026-09-25 — Please delete the stale spike shortcuts in Shortcuts.app (the CLI has no
  delete), **especially `imcp-spike-notes-append-find` and `imcp-spike-notes-append-id`**
  (unsafe: they can act on an arbitrary note). Test data to remove when convenient:
  notes titled "imcp-spike …", 1 CotEditor document.

- 2026-09-25 — **M0 live half (tech-notes §9 q1–q9).** Needs the user's OK to sign
  (`shortcuts sign --mode people-who-know-me` first; `anyone` only if needed), import
  (user clicks "Add Shortcut" per wrapper), run each once in Shortcuts.app with
  "Always Allow", then run via `Spike/run.py`. Test data it creates: 1–3 reminders
  titled "imcp-spike …", 1 note "imcp-spike note", 1 untitled CotEditor document, one
  MacWhisper transcription of a short test audio file. All removable afterwards.
  Also needs: confirmation the Mac is signed into iCloud (couldn't read it without
  touching account data).

## Later
