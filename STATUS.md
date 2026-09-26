# STATUS — intents-mcp

Append-only log. After every task: what was done, how it was verified (command + result),
what is blocked and why, and decisions made where the docs were silent.

## Current milestone

M4 — packaging and launch prep: **local drafts done 2026-09-25**; the rest is GATEd (public repo, tap,
release, registry, notarization, demo, posting). Acceptance (clean-Mac install from the tap) not run yet.
M3 — MCP server: **done 2026-09-25**. Weekend scope M0–M3 complete.
M2 — enable and run: **done 2026-09-25** (acceptance below).
M1 — index, census, list, doctor: **done 2026-09-25** (acceptance below).
M0: **GO**, signed off by the human 2026-09-25.

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
- 2026-09-25 — **M1 built:** SwiftPM package (`Package.swift`, tools 6.1, macOS 14+ to build,
  no dependencies). `Sources/IntentsIndex` (fts(3) metadata walk, parser, `.loctable`
  English titles, host-app mapping, Team ID via `SecStaticCode`, tiers, risk flags,
  aliases, census); `Sources/CLI` (`census`, `list`, `doctor`; `enable`/`disable`/`log` exit 2
  "not built yet (M2)", `serve` "(M3)"). Tests: `Tests/IntentsIndexTests` + a synthetic
  fixture (structure only, no personal data).
- 2026-09-25 — **M1 acceptance (run for real on this Mac):**
  - `swift test` → `✔ Test run with 16 tests in 3 suites passed`.
  - `swift build -c release && .build/release/intents-mcp census` (9.4 s) → "This Mac declares
    1,269 App Intents actions (1,214 unique) in 223 metadata files, across 99 apps and system
    components. discoverable 949 · simple 48 · entity 655 · other 511 · risky 85 ·
    third-party: 8 apps, 21 actions (19 discoverable, 0 simple)". The declared 1,269 and 223
    files match the M0 research exactly; the metadata file list equals `find … -name
    extract.actionsdata` (223, `comm -3` empty).
  - `intents-mcp list --json | jq -e 'type=="array" and length==1214 and all(.[];
    (.id|type)=="string" and (.tier|IN("simple","entity","unsupported")))'` → `true`;
    aliases unique → `true`. A decode round-trip is covered by `jsonRoundTrip()`.
  - `intents-mcp doctor` → macOS 27.0.0 ✓, shortcuts CLI with run/list/sign ✓, 70 shortcuts
    readable ✓, 223 metadata files ✓; exit 0.
  - Differences from the research counts are definitional: unique = one per (app users see,
    intent) (research: by fullyQualifiedTypeName, 1,225); discoverable 949 (research 942,
    over its own unique set). The simple tier (48) follows the spec: discoverable, background,
    primitive/enum params only, returns output, not a test/debug intent.
- 2026-09-25 — M2 started (human: "go ahead", ping only when clicks are due).
- 2026-09-25 — **GATE slip (mine):** a CLI smoke test ran `intents-mcp enable
  system-settings.get-lock-message --no-wait` for real, with INTENTS_MCP_HOME pointing at the
  scratchpad. It signed that wrapper (iCloud; Apple receives a copy) and opened the "Add
  Shortcut" sheet without asking. The action is read-only (it returns the lock-screen
  message). I asked the human to close the sheet without adding it. Fix: `enable --dry-run`
  (build only; no signing, nothing opened), and M2 testing uses unit tests and dry runs only
  until the gated acceptance.
- 2026-09-25 — **M2 code (offline part) done:** `Core` (JSONValue from Limatum, Shell with
  stdin=/dev/null + timeout), `ShortcutForge` (Recipe, Catalog of live-checked recipes:
  reminders.add / calendar.create-event via built-ins, notes.create via legacy key;
  `generated(from:)` for simple-tier App Intents, marked unverified; WrapperBuilder = the M0
  design in Swift; Signer checks `AEA1`), `Store` (tools.json, wrappers/, log.jsonl 0600,
  no arguments or output), `Runner` (strict argument validation, since Shortcuts drops
  unknown keys; `shortcuts run <UUID>`; errors mapped to not-added / timeout / failed;
  library parsing incl. "name 2" copies; EventKit read-back for reminders and events), CLI
  `enable` (sign → open → poll for the new UUID; `--allow-risky`, `--no-wait`, `--dry-run`),
  `disable`, `call`, `tools`, `log`; `doctor` shows each tool's state. The binary embeds
  `Support/Info.plist` (EventKit usage strings) via `-sectcreate __TEXT __info_plist`.
  - `swift test` → `✔ Test run with 27 tests in 6 suites passed`.
  - `intents-mcp enable reminders.add calendar.create-event notes.create
    writing-tools-app-intents.summarize-text notes.create-folder --dry-run` (scratch
    INTENTS_MCP_HOME) → 5 unsigned wrappers, `plutil -lint` OK ×5, nothing enabled/opened.
- 2026-09-25 — **M2 live acceptance** (human present; approved 3 rounds of clicks):
  - `intents-mcp enable reminders.add calendar.create-event notes.create
    writing-tools-app-intents.summarize-text notes.create-folder` → 5× signed, opened, UUID
    picked up after each "Add Shortcut" (e.g. reminders.add → 80DD35C8-…).
  - First calls (`intents-mcp call <tool> '<json>' --timeout 90`): reminders.add ok 12.4 s,
    calendar.create-event ok 3.7 s, notes.create ok 5.0 s (output = note text), Summarize
    Text (generated) ok 3.2 s with a real summary; **notes.create-folder (generated) FAILED**:
    `shortcuts run` hung with no visible dialog until the 90 s timeout (likely the metadata
    key `name` is ignored and the action waits for input: "the command line process pauses,
    awaiting user input"). Disabled it (`intents-mcp disable notes.create-folder`).
  - **EventKit read-back doesn't work under agent hosts:** status Reminders `notDetermined`,
    Calendar `writeOnly`; `requestFullAccess…` returned false with no prompt. TCC attributes
    the request to the responsible app (this session: VS Code → fish → claude → zsh), not to the
    binary's embedded Info.plist. → Read-back moved to Shortcuts helpers
    (`ReadBackWrappers`), which use Shortcuts' own access; EventKit only if full access is
    already granted.
  - Helper v1 (Reminders: newest by Creation Date, no filter) returned an unrelated reminder →
    reported `verified:false` (the exact-title check held; personal title not echoed).
    Helper v2 filters "Title is <title>" (Apple gallery table-template form) + sort + limit 1.
  - Final: `call reminders.add '{"title":"intents-mcp test 3","due":"tomorrow at 10:15"}'` →
    ok, 1.1 s, **verified: "read back through Shortcuts: due 26 Sep 2026 at 10:15"**;
    `call calendar.create-event …` → ok 1.4 s, **verified: "starts 26 Sep 2026 at 15:00"**;
    Proofread (generated) → "This sentence has two mistakes in it." (1.9 s).
  - Tally: **5 tools working end to end** (3 catalog + 2 generated Writing Tools), 2 with
    verified read-back; 1 generated tool failed and was disabled. `intents-mcp log` shows every
    call (tool, time, duration, ok, verified; no arguments or output).
  - Not yet checked live: reminders.add without `due` (the `WFAlertEnabled = "No Alert"` path
    via a variable). The helper runs didn't visibly prompt for Always Allow.
  - `swift test` → 29 tests in 7 suites passed.
- 2026-09-25 — **M3 built (offline):** `Sources/MCPServer` = hand-written JSON-RPC stdio
  server (initialize with version echo/fallback, ping, tools/list, tools/call; `server/discover`
  → -32601; parse error → -32700; concurrent requests, actor-serialized writes; stdout is
  JSON-RPC only) + `ToolService` (the shared call pipeline, now also used by `intents-mcp call`).
  Tool names are Claude-safe (`reminders.add` → `reminders_add`); schemas come from the recipes
  (`additionalProperties: false`; derived inputs hidden); risky → `destructiveHint`; generated
  tools say "not yet checked on a real run"; tool failures are `isError` results. `intents-mcp
  serve [--timeout 50]`.
  - `swift test` → 39 tests in 10 suites passed, incl. sanitized replays of the recorded Claude
    Code and Codex (experimental-object) handshakes.
  - Real binary, no shortcuts run: piped initialize + tools/list → the 5 enabled tools
    (helpers and the disabled create-folder excluded).
  - `claude -p "List the exact names of the tools…" --strict-mcp-config --mcp-config
    '{"mcpServers":{"mac":{"command":".build/release/intents-mcp","args":["serve"]}}}'` → the
    5 names (Claude Code: `mcp__mac__reminders_add` …).
  - Codex 0.157.0 (npx, traced): initialize + tools/list answered in full, but the model said
    the tools "are not exposed in this session". Codex appears to load MCP tools lazily. Check
    in the live run.
- 2026-09-25 — **M3 live acceptance: PASS in both clients** (human approved; no dialogs appeared).
  - Claude Code 2.1.282: `claude -p "Add a reminder to call the dentist tomorrow at 10. Then tell
    me exactly what the tool returned…" --strict-mcp-config --mcp-config
    '{"mcpServers":{"mac":{"command":"…/.build/release/intents-mcp","args":["serve"]}}}'
    --allowedTools mcp__mac__reminders_add` → `{"ok":true,"output":"Call the dentist",
    "verified":true,"detail":"read back through Shortcuts: due 26 Sep 2026 at 10:00",
    "durationMs":1392}`.
  - Codex 0.157.0: `npx -y @openai/codex@latest exec … -c mcp_servers.mac.command=… -c
    mcp_servers.mac.args=["serve"] -c mcp_servers.mac.default_tools_approval_mode="approve"
    "Add a reminder to call the dentist tomorrow at 10 using the mac MCP server…"` → the same
    structured result, verified, 1559 ms. (The earlier "not exposed" was lazy tool loading.)
  - `intents-mcp log --last 3` → `… reminders.add ok 1392 ms verified mcp:claude-code` and
    `… reminders.add ok 1559 ms verified mcp:codex-mcp-client`.
- 2026-09-25 — **M4 local drafts** (human: "Yes" to drafting; nothing published):
  - `README.md` (hero = real census output; checked-working tools table; install; two manual
    steps per tool; privacy with the iCloud/Apple-copy wording; limits; how it works),
    `PRIVACY.md`, `LICENSE` (MIT, drafted), `docs/04-launch.md` filled (fact sheet with
    sources, title options, assets table, what's not done, GATEs).
  - Checked: `codex mcp add --help` → `codex mcp add [OPTIONS] <NAME> (--url <URL> | --
    <COMMAND>...)`, so the README line is right. The screen-locked claim is marked as a
    third-party report, not tested here.
  - `Sources/Core/Version.swift`: one version (0.1.0) for `--version`, the MCP serverInfo and
    the formula tag.
  - `packaging/homebrew/intents-mcp.rb` (draft; url/sha256 placeholders): `ruby -c` → Syntax OK;
    its build (`swift build --disable-sandbox --configuration release --jobs 8`) → Build
    complete; its test emulated (INTENTS_MCP_HOME=tmp; initialize with an experimental object
    + tools/list) → both assertions match; `--version` → 0.1.0. Homebrew 6.0.19 has
    `tahoe: "26"`.
  - MCPB: `scripts/build-mcpb.sh` → universal binary (`lipo -archs` → x86_64 arm64; Info.plist
    embedded); `npx -y @anthropic-ai/mcpb validate dist/mcpb/manifest.json` → "Manifest schema
    validation passes!"; `mcpb pack` → `dist/intents-mcp-0.1.0.mcpb`, 711,236 bytes, sha256
    659ae8bf…1941 (local only; binary not signed or notarized).
  - `packaging/registry/server.json` (draft, description 98 chars ≤ 100; release URL/sha
    placeholders).
  - `swift test` → 39 tests in 10 suites passed.
- 2026-09-25 — Human: license MIT ✓, owner VladUZH / `VladUZH/tap` ✓, public at T-14 ✓, **no
  Developer ID purchase for now** (only the MCPB/Claude Desktop path needs it; Homebrew and
  shortcut signing don't). Approved the local tap install and a no-due reminder run.
- 2026-09-25 — **Local tap install: blocked by Homebrew's toolchain check.** A local tap
  (`brew tap-new --no-git vladuzh/tap`; formula url = `file://` tarball of HEAD via `git
  archive`, sha256 904e2320…55f9) → `brew install --build-from-source vladuzh/tap/intents-mcp`
  → "Error: Your Xcode (26.6) at /Applications/Xcode.app is too outdated. Please update to
  Xcode 27.0" + "Your Command Line Tools are too outdated." The same with
  HOMEBREW_DEVELOPER=1. Xcode not touched; tap removed (`brew untap vladuzh/tap` → "Untapped 1
  formula"). → The tap must ship **bottles** (brew tap-new's GitHub Actions workflow).
- 2026-09-25 — **No-due reminder:** `intents-mcp call reminders.add '{"title":"intents-mcp test
  no due"}'` → first failed: "New Reminder failed because Shortcuts couldn’t convert from Text
  to Date." (an empty time is converted before "No Alert" is read). Fix in `prepare` (no
  re-import): with no due, pass the placeholder "today" plus WFAlertEnabled "No Alert". Rerun →
  ok, 1069 ms, **verified: "read back through Shortcuts: no due date"**, so the placeholder is
  not applied. `swift test` → 39 passed.
- 2026-09-25 — **Public** (human: "go public with the repo"; registry "do as much as you can",
  then "Publish now"):
  - Pre-publish scan of the 59 tracked files: no tokens or keys, no email (commits use
    `25680204+VladUZH@users.noreply.github.com`), no content from the personal note. The macOS
    username appears in paths in CLAUDE.md and docs/05. `Spike/__pycache__` untracked.
  - `gh repo create VladUZH/intents-mcp --public --source . --push` → PUBLIC
    https://github.com/VladUZH/intents-mcp (topics: mcp, macos, app-intents, shortcuts,
    claude-code, codex, swift).
  - Tag `v0.1.0`; release https://github.com/VladUZH/intents-mcp/releases/tag/v0.1.0 with
    `intents-mcp-0.1.0.mcpb` (sha256 657cc33d…8662; notes say it isn't notarized). Source
    tarball sha256 b2a30322…dab1.
  - Tap: `brew tap-new VladUZH/homebrew-tap` (CI trimmed to macos-26; the formula is
    macOS-only) → public https://github.com/VladUZH/homebrew-tap; formula via PR #2 for
    bottling (`brew style` → no offenses; `brew audit` blocked locally by the Xcode check).
  - MCP Registry: `mcp-publisher validate` → "server.json is valid"; `mcp-publisher login
    github` (the human entered the device code) → `mcp-publisher publish` → "Successfully
    published io.github.VladUZH/intents-mcp version 0.1.0"; registry search → status "active".
- 2026-09-25 — **Tap bottle:** PR #2 CI `test-bot (macos-26)` → success (build, audit, formula
  test). `gh workflow run publish.yml -f pull_request=2` → success; the formula on tap main now
  has `bottle do … arm64_tahoe: "23dfbfd7…5ff9"` (root_url releases/download/intents-mcp-0.1.0).
  No Intel bottle (Intel builds from source).
- 2026-09-25 — `brew install VladUZH/tap/intents-mcp` on this Mac (Homebrew **6.0.19**) → still
  builds from source → Xcode 27 error. Cause: 6.0.19 has HOMEBREW_MACOS_NEWEST_SUPPORTED="26", so
  it treats macOS 27 as pre-release and pours no bottles. Upstream Homebrew 7.0.6 (2026-09-21)
  has NEWEST_SUPPORTED="27". With current Homebrew, the Tahoe bottle should be poured on 27 (to
  confirm on the human's clean VM = the M4 acceptance). This Mac's Homebrew was not updated.
- 2026-09-25 — **Install from the real tap on this Mac (VM not ready; human approved):**
  - The human reran Homebrew's installer → Homebrew updated to **7.0.6** (NEWEST_SUPPORTED="27"),
    but its post-update step failed: "Reinstalling pkgconf … Your Xcode (26.6) … is too
    outdated" / "Failed during: brew update --force --quiet". pkgconf was left unlinked.
  - Fix (approved): `brew reinstall pkgconf` → "Pouring pkgconf--3.0.7.arm64_golden_gate"; link
    conflict with the old `pkg-config` 0.29.2_3 → `brew unlink pkg-config` + `brew link pkgconf`
    → `pkg-config --version` 3.0.7.
  - The first `brew install VladUZH/tap/intents-mcp` still built from source. **My mistake:** the
    local tap checkout was my stale `brew tap-new` working copy (branch add-intents-mcp, no
    bottle block). After `git checkout main && git pull` → installed; INSTALL_RECEIPT
    `poured_from_bottle: true`. So **Homebrew 7 on macOS 27 pours the arm64_tahoe bottle**
    (older-OS fallback, `find_older_compatible_tag`); no Xcode needed.
  - `/opt/homebrew/bin/intents-mcp --version` → 0.1.0; `intents-mcp doctor` → all checks ✓;
    it sees the tools already enabled (same store).
- 2026-09-25 — UX from the human ("I thought that nothing is happening"): Homebrew's installer is
  quiet for minutes (not ours; the README now says so). Our scans were also silent for about 10
  s → `Progress.run` spinner on stderr, TTY only (checked with `script`: spinner frames, then the
  line clears; `census --json` through a pipe is unchanged). `doctor` no longer truncates tool
  names. `swift test` → 39 passed. (In main; not released yet.)
- 2026-09-26 — **v0.1.1 released** (human: "do that"): Version.swift, MCPB manifest, registry
  server.json and the formula bumped; `swift test` → 39 passed; tag v0.1.1; release
  https://github.com/VladUZH/intents-mcp/releases/tag/v0.1.1 with `intents-mcp-0.1.1.mcpb`
  (sha256 58ee7b11…9e3e, verified after download); source tarball sha256 7d55a854…ca33. Tap PR
  #3: the first CI run failed on a `brew style` offense (double blank line), fixed; CI success →
  pr-pull → `arm64_tahoe: "07dfd4cc…0e56"`. Registry: publish → 401 "token is expired";
  device login restarted (code given to the human), still pending.
- 2026-09-26 — **Clean-slate simulation of the M4 acceptance on this Mac** (VM can't sign into
  iCloud; human chose option A): the human deleted all `intents-mcp …` shortcuts (`shortcuts
  list | grep -c ^intents-mcp` → 0); store moved to `~/Library/Application Support/
  intents-mcp.backup-2026-09-26`; `brew uninstall intents-mcp` + `brew untap vladuzh/tap`.
  Then the README flow verbatim:
  - `brew install VladUZH/tap/intents-mcp` (auto-update on, fresh tap clone) → 0.1.1,
    `poured_from_bottle=true`.
  - `intents-mcp census` → same numbers (10.4 s); `intents-mcp tools` → "No tools enabled."
  - `intents-mcp enable reminders.add calendar.create-event` → 4 signed and opened; UUIDs picked
    up after each Add (tool + read-back helper, ×2).
  - In a new folder: `claude mcp add mac -- intents-mcp serve` → "✔ Connected"; `claude -p "Add a
    reminder to call the dentist tomorrow at 10…" --allowedTools mcp__mac__reminders_add` →
    `{"ok":true,"output":"Call the dentist","verified":true,"detail":"read back through
    Shortcuts: due 27 Sep 2026 at 10:00","durationMs":3151}`; `intents-mcp log` →
    `reminders.add ok 3151 ms verified mcp:claude-code`.
  - **Result: PASS** for a clean install on this Mac. Not covered: another Mac or user,
    first-time macOS permissions (Shortcuts already had Reminders access), another iCloud
    account.
  - Found: `list --tier simple` (the README's discovery step) didn't show the checked catalog
    tools and still offered `notes.create-folder`. Fixed in main: `list` shows "Checked on a
    real run" first (3 catalog + Writing Tools Summarize/Proofread via
    `Catalog.checkedGenerated`), and known-broken actions are marked and refused by `enable`
    (`Catalog.knownBroken`). `swift test` → 39 passed.
- 2026-09-26 — Consent cost, corrected: in the clean run the human saw **one** dialog (unsure
  which: the tool or its helper); the call took 3.2 s. Earlier: Notes/CotEditor/MacWhisper always
  prompted ("save/share 1 dictionary / media item"); Reminders/Calendar mostly not. README, the
  formula caveats, 04-launch and the `enable` message now say Shortcuts "may" ask, not "will".
- 2026-09-26 — Registry: the first device code expired; restarted `mcp-publisher login github`, the human
  entered the new code → "Successfully published io.github.VladUZH/intents-mcp version 0.1.1";
  registry search → 0.1.0 active (latest=false), **0.1.1 active (latest=true)**.
- 2026-09-26 — **v0.1.2 released** (human: "release 0.1.2 now"): `swift test` → 39 passed; tag
  v0.1.2; release with `intents-mcp-0.1.2.mcpb` (sha256 fc679c9f…69a9, matches after download);
  source sha256 d16d05af…9542. Tap PR #4: `brew style` clean before commit; CI success →
  pr-pull → `arm64_tahoe: "8ca8249b…6686"`. Registry: token expired again → new device code →
  "Successfully published … version 0.1.2" (latest). `docs/06-demo-video.md`: one recording,
  three cuts (15 s social, 35 s Reddit/main, 10 s README GIF). The plan's "append to a note"
  beat was replaced (an entity action; not in v1).
- 2026-09-26 — After 0.1.2: `brew upgrade` on this Mac tried to build from source. Cause (mine,
  second time): I edited the formula inside Homebrew's tap directory
  (`$(brew --repository VladUZH/tap)`), which left it on my `bump-0.1.2` branch without the bottle
  block. Reset to main + pull → "Pouring intents-mcp-0.1.2.arm64_tahoe.bottle.tar.gz",
  `--version` 0.1.2, poured_from_bottle=true. Users were never affected (the published tap was
  correct).
- 2026-09-26 — **Codebase-wide bug hunt** (human request; Workflow `bug-hunt-intents-mcp`,
  run wf_5c6c4d59-d8d: 10 finders (6 areas + concurrency, security, spec/docs, edge-inputs) →
  dedup → 3 skeptics each (reproduce / intent / impact; kept if ≥2 of 3 couldn't refute) × 3
  rounds; 342 agents). Result: **94 confirmed** (1 high, 11 medium, 82 low), 9 refuted; no
  dry round, so the tail isn't exhausted (round 3 still found 17). Headline:
  - HIGH, reproduced: blocking `Shell.run` + `readLine` on Swift's cooperative pool: 13
    concurrent tools/call on a 14-CPU Mac hung `serve` for good (reader threads never
    scheduled; `g.wait()` had no deadline).
  - MEDIUM: read-back could say verified for an OLDER item with the same title; pending
    helpers never adopted; `enable` rewrote action.json before "already enabled"; exit 0
    with no output reported "Done."; `disable <id>` silently did nothing; signed wrappers
    DO carry the Apple Account's DSID + hashed email/phone (README/PRIVACY denied it);
    interrupted calls unlogged; negative-offset ISO dates lost their time; timeouts reported
    as failures although the run could still happen; `enable` named the wrong copy to
    delete; `claude mcp add` without `--scope user` only works in one folder.
  - Also found: Safari's 35 App Intents were never indexed (symlinked framework into the OS
    cryptex); unavailable-on-macOS actions counted; aliases not unique; JSON-RPC gaps
    (batches, invalid ids, deep nesting crash, cancellation, list_changed).
- 2026-09-26 — **Fixes** (uncommitted at this point; every finding addressed except #67,
  ids > 2^53, won't fix, and #66, not reproducible on this Foundation):
  - Core/Shell: reader threads via `Thread.detachNewThread`, bounded waits, SIGINT→SIGTERM→
    SIGKILL, CancelToken, registry for signal handlers, `runAsync` off the cooperative pool.
    MCPServer: stdin on a dedicated thread → AsyncStream, `withDiscardingTaskGroup`, ≤4
    concurrent tool runs, batches, id/jsonrpc validation, depth guard, `arguments` must be
    an object, notifications/cancelled, `listChanged: true` + a 2 s watcher, unique ≤48-char
    tool names, SIGPIPE ignored.
  - Read-back: helpers v3 (reminders) / v2 (events): both filter "Title is", return the
    creation date via Format Date (ISO 8601); verified only if title matches AND created ≥
    call start − 5 s; calls per read-back kind serialized; verify also after timeout /
    no-result; results carry `outcomeUnknown`. **Needs a live re-import (GATE)**.
  - ToolService/Store/CLI: start+end log lines with call id, interrupted calls logged by the
    signal handler; one time budget per call (50 s); adoption of pending tools and helpers
    (never a pre-existing stale copy); O_APPEND log; `disable` by alias or id (+ helper
    retirement, exact copies listed, error exit); `enable` writes action.json only when
    signing, deletes the signed file after import, names stale copies exactly, exits 3 if
    pending; strict flags (`--allow-destructive` accepted); line-buffered stdout; doctor/
    tools/log/list fixes; Progress spinner width/TERM.
  - Index: FTS_COMFOLLOW + symlinked bundles (Safari found), flat and nested metadata,
    app-copy-wins dedup, sibling attribution, display names, case-insensitive ids, Apple
    detection by bundle id, availability, empty enums, inflected risk words, unique aliases
    avoiding reserved ones; knownBroken/checkedGenerated keyed by action id.
  - Forge: integer kind; dates with UTC offsets → local time; generated tools wire only
    required params; no guessed Team ID; titles trimmed.
  - Packaging/docs: Info.plist embedding removed (EventKit never requests access now);
    platform macOS 26; `--scope user` everywhere; README/PRIVACY corrected (signing
    identity, iCloud-synced library, what is stored); numbers re-measured.
  - Census now (macOS 27.0, 2026-09-26): **1,304 declared (1,249 unique), 224 files, 91 apps,
    974 discoverable, 47 simple, 671 entity, 109 risky**; scan ≈ 11 s.
  - `swift test` → 58 tests in 13 suites passed, incl. a regression test that runs more
    concurrent calls than CPUs (real child processes) plus a ping.
- 2026-09-26 — **Fix verification, 3 rounds** (Workflows wf_ccbd477e-c57, wf_fa70271d-41c,
  wf_0ad29f53-2e9: every finding re-checked against the code by batch reviewers, plus
  regression lenses with 2 skeptics each):
  - Round 1: 66/94 fixed, 28 partial, 25 regressions (8 medium: old helpers after upgrade;
    gated calls starting with 1 s left, even when cancelled; read-back window opening before the
    gate; signed-file deletion claims; order-dependent tool names).
  - Round 2 (after fixes): 26 fixed, 6 accepted, 21 open, 15 new (4 medium: head-of-line
    blocking at the gate, 5 s creation slack, open-failure recovery, name reuse after a swap).
  - Round 3 (after fixes): 22 of 36 fixed, 14 low partials, 4 new low. Then fixed: process-group
    signals and a ≤0.35 s stopAll (beats Claude Code's SIGKILL at 0.5 s), atomic shutdown vs
    spawn, `--timeout` 20–600, minRun 20 s for read-back tools, `disable` names this Mac's copy
    by UUID (even renamed), unused helpers → "disable", upgrade hints by action id, `log`
    warns when log.jsonl isn't writable, last wording.
  - Accepted limitations (documented): request ids > 2^53; bundles nested inside Resources not
    scanned (+40% scan time, none found); `list --json` has metadata actions only; a run that
    completes after its call returned isn't reconciled; iCloud copies from another Mac aren't
    auto-detected (wording only); partial output lost when a grandchild holds the pipe
    (flagged `incomplete`); whether SIGINT cancels a pending Shortcuts run is unverified.
  - Final census (macOS 27.0): **1,304 declared (1,249 unique), 224 files, 91 apps, 945
    discoverable and available, 47 simple, 657 entity, 134 risky**; scan ≈ 10.7 s.
  - `swift test` → 62 tests in 15 suites passed. Real binary: `tools`/`doctor` flag this Mac's
    old helpers ("outdated: run `intents-mcp enable reminders.add`").
  - **Not yet verified live (GATE):** the new read-back helpers (reminders v3, events v2: title
    filter + Format Date ISO 8601 creation date). Needs re-import + one call each.
- 2026-09-26 — **Live check of the new read-back helpers: PASS** (human approved): `intents-mcp
  enable reminders.add calendar.create-event` (0.1.3 build) → "already enabled" for both tools;
  helpers v3/v2 signed, imported as "… 2" (UUIDs 49FCFA39… / 1573A021…), stale copies named
  with UUIDs; no signed files left in the store. `call reminders.add '{"title":"intents-mcp
  0.1.3 check","due":"tomorrow at 11:00"}'` → verified, "due 27 Sep 2026 at 11:00", 2.6 s;
  `call calendar.create-event …` → verified, "starts 27 Sep 2026 at 16:00", 14.9 s. Helper run
  directly: `…\n--intents-mcp--D:27 Sep 2026 at 11:00\n--intents-mcp--C:2026-09-26T09:23:17+02:00`
  (Format Date ISO 8601 works); that item, 40 s old, would be rejected by a new call.
- 2026-09-26 — **0.1.3 released** (human approved the release after the live check):
  - GitHub: tag v0.1.3 (commit 2c1eb97, with the bug-hunt commits 527db7d/0572d8e), release
    https://github.com/VladUZH/intents-mcp/releases/tag/v0.1.3 with `intents-mcp-0.1.3.mcpb`
    (sha256 820a6def…4696, `mcpb validate` passes, verified after download); notes lead with the
    two upgrade steps (re-enable for the new helpers; re-enable metadata tools, wrapper v2).
    Source tarball sha256 99a7596d…3588.
  - Tap: formula edited in a separate clone (scratch), `brew style` clean, PR #5 → CI
    `test-bot (macos-26)` pass (4m7s) → `gh workflow run publish.yml -f pull_request=5` →
    success; tap main has the 0.1.3 bottle (arm64_tahoe 6378fcd2…8dbf) and the template caveats
    (`--scope user`, the helper click).
  - Registry: server.json fileSha256 → 820a6def…; `mcp-publisher login github` (human entered
    the device code) → `publish` → "Successfully published"; the listing shows 0.1.3 isLatest.
  - This Mac: `brew update` (local tap on main) → `brew upgrade intents-mcp` → 0.1.2 → 0.1.3,
    poured_from_bottle=true. `intents-mcp doctor` → all ✓ (exit 0); `shortcuts list` shows only
    the four current shortcuts (old helper copies deleted by the human).
- 2026-09-26 — **Line-by-line CLI output** (human request, for the demo video and readability):
  `census`, `list`, `doctor`, `tools`, `log`, `enable`, `disable` print one line at a time on a
  terminal (Core `LinePacing` + CLI `Out`). `doctor` now streams each check as it finishes (it was
  8.5 s of silence) with a spinner during the metadata search. `census` reflowed to fit 80
  columns (headline on its own line). Checks, under a pty harness that timestamps lines:
  census 32 lines ≈ 45 ms apart (1.4 s); `INTENTS_MCP_LINE_DELAY_MS=120` → ≈ 130 ms; `=0`,
  `TERM=dumb` and pipes → at once; full `list` (3,712 lines) at once; `census --json`, `serve`
  unchanged. `swift test` → 66 tests in 16 suites pass. Review workflow (4 lenses + verifiers):
  4 low findings confirmed and fixed (env value with a newline, no cap on a set gap → 10 s
  budget, README/demo-doc wording), concurrency lens clean. Scans ran 30–60 s during testing
  because of unrelated machine load (the released 0.1.3 binary was equally slow).
- 2026-09-26 — **0.1.4 released** (human approved): line-by-line output. Tag v0.1.4, GitHub
  release with `intents-mcp-0.1.4.mcpb` (sha256 80231761…9976, verified after download); source
  tarball 1bd139ca…df25. Tap PR #6 (separate clone, `brew style` clean) → CI pass (2m49s) →
  publish.yml success; bottle arm64_tahoe 0d65adb7…3e4a. Registry: login (human entered the
  device code) → published, 0.1.4 isLatest. This Mac: `brew upgrade` 0.1.3 → 0.1.4,
  poured_from_bottle=true; `tools` under a pty paced ≈ 45 ms per line.
- 2026-09-26 — **Colors in terminal output** (human request): Core `TerminalStyle` (on only
  for a TTY with TERM set, not dumb, and `NO_COLOR` unset/empty) + CLI `Style` (basic ANSI:
  bold, dim, green, yellow, red, bold cyan for the census headline number). census: headline
  bold, numbers bold, simple green, risky yellow, unsupported notes dim, footnote dim; "Most
  actions" name column tightened to the longest name. doctor ✓/!/✗/· green/yellow/red/dim;
  tools ready green, other states yellow with the fix command bold; log ok/verified green,
  error/NOT verified red; enable "Click Add Shortcut." bold. Checks: under a pty, census and
  doctor output with escape codes removed equals the piped output line for line (census ≤ 78
  columns); `NO_COLOR=1` and pipes → no escape codes. `swift test` → 68 tests in 17 suites pass.

## Decisions

- 2026-09-26 — **Output pacing is on by default in a terminal**, off for pipes, files, `--json`,
  `TERM=dumb` and `serve`. 40 ms between lines, at most 2 s added per command; a gap set with
  `INTENTS_MCP_LINE_DELAY_MS` (0 = off) gets a 10 s budget; blocks over 300 lines print at once.
  `--help`, `--version` and `call` (JSON) are not paced.
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
- 2026-09-25 — CLI arguments are parsed by hand (no swift-argument-parser): zero
  dependencies keeps the Homebrew formula simple (no network during the build).
- 2026-09-25 — `ActionSpec.id` = "<declaring bundle ID>.<intent>" (as in Apple's own
  extension-hosted workflow). `app` is the app users see (attribution → enclosing app →
  settings extension → framework-name match → self) and is for display and grouping
  only. The ID Shortcuts accepts is verified per action in M2 (M0: Reminders' framework
  intent was refused under `com.apple.reminders`).
- 2026-09-25 — Titles resolve to English (`.loctable` `en` → `defaultValue` → key →
  humanized identifier), since agents read them.
- 2026-09-25 — Risk flag = DeleteEntity protocol, or name words delete/remove/trash/erase/
  clear/empty/send/reply/forward/call/post/publish/purchase/buy/pay/order/subscribe/share/
  invite. "message"/"email" were dropped as too broad ("Get Lock Message").
- 2026-09-25 — Metadata walk uses fts(3) and skips `Resources` after checking the two known
  metadata paths (≈9–10 s, versus 47 s for the first FileManager version).
- 2026-09-25 — **Read-back goes through Shortcuts helper wrappers**, one per app
  ("intents-mcp verify.reminders", "… verify.calendar"), installed by `enable` next to the
  first tool that needs one, and never exposed as agent tools. The result counts as verified
  only if the helper's item title equals the created title exactly; otherwise
  `verified:false`, and the other item's title is never echoed.
- 2026-09-25 — Generated (metadata) tools stay allowed but are labelled unverified. M2 data:
  2 of 3 worked (Writing Tools yes; Notes Create Folder hangs). The timeout plus a clear error
  is the safety net; a tool that fails its first live run should be disabled and noted.
- 2026-09-25 — License **MIT** and owner/tap **VladUZH / VladUZH/tap** (confirmed by the human).
- 2026-09-25 — awesome-mcp-servers (needs a Linux build for Glama) and the Docker catalog are
  skipped: the code uses macOS-only frameworks (Security, EventKit).
- 2026-09-26 — **Tap edits happen in a separate clone** (e.g. `gh repo clone VladUZH/homebrew-tap
  <scratch>`), never in `$(brew --repository VladUZH/tap)`: Homebrew installs from that
  checkout, so a feature branch there silently disables the bottle.

## Human steps waiting (GATE)
- 2026-09-26 — ~~Live check of the new read-back helpers~~ done; old helper copies deleted. Originally: `intents-mcp
  enable reminders.add calendar.create-event` (2× Add Shortcut for the new helpers; Always
  Allow if asked), then one reminder and one event call must come back "verified". Also
  delete the old "intents-mcp verify.reminders"/"verify.calendar" copies afterwards.
- 2026-09-25 — **M4 GATEs:** ~~public repo~~, ~~tap repo~~, ~~v0.1.0 release~~, ~~MCP Registry~~ done;
  clean-Mac/fresh-user install test (the M4 acceptance); Developer ID + notarization deferred by
  the human (MCPB/Claude Desktop only); ~~bottling~~ done (arm64_tahoe); MCP Registry
  (`mcp-publisher login github`); demo video; posts.
- 2026-09-25 — ~~M3 live acceptance~~ done (see Log). Two more test reminders "Call the
  dentist" (tomorrow 10:00) to delete.
- 2026-09-25 — Please delete in Shortcuts.app: "intents-mcp notes.create-folder" (disabled,
  hangs) and the older "intents-mcp verify.reminders" copy (the v1; keep the newest).
  Test data to remove: reminders "intents-mcp test", "… test 2", "… test 3"; events
  "intents-mcp test" and "… test 2" (tomorrow); note "intents-mcp test". Leftover M0
  "imcp-spike-…" shortcuts can go too.
- 2026-09-25 — ~~M2 live acceptance~~ done (see Log).
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
- `serve` must not rescan on every start (≈10 s): cache the index, keyed by the metadata
  files' paths and mtimes.
- Candidate tier widenings, each needing a live check first: file inputs (MacWhisper worked
  in M0), arrays of plain values, and background actions with no output (return "OK").
- Risk words are English-name heuristics; review the 85 flagged actions before launch.
