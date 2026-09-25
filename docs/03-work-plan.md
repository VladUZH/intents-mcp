# 03 — Work plan

Time box: M0 is a 1–2 day spike with a go/pivot decision; M1–M3 over a long weekend;
M4 over the following days.

## M0 — Feasibility spike (1–2 days). Go/pivot gate.

**GATE (human) before starting:** the user must OK creating, signing, importing and
running test shortcuts on this Mac, be signed into iCloud, and be present to click
"Add Shortcut" and "Always Allow".

Answer `tech-notes.md` §9 by experiment, with hand-built code on:
- 2 simple actions (primitive parameters, background-capable), e.g. Reminders "Add
  Reminder" and one more from the 129 simple ones;
- 1 entity action (e.g. append to an existing note) to test entity passing;
- 1 third-party app action.

For each: build the wrapper, sign (try `people-who-know-me` first), add, set "Always
Allow", run with JSON input from a process whose stdin is redirected, read the output,
measure cold and warm latency, and try a wrong parameter key.

Also: test the MCP handshake with both Claude Code and Codex, using the Swift SDK and a
minimal hand-written JSON-RPC server, and pick one.

**Accept (go):** both simple actions and the third-party action run end to end with
parameters and return output, and the handshake works with both clients.
**Entity result:** either a working encoding (then entities are in scope for M2) or a
documented "not yet" (then v1 ships the simple tier only). Record it in `STATUS.md`.
**Pivot options** if the simple path fails: generate wrappers the user edits once, or use
Limatum's Apple Events drivers for the same apps. Decide before M1.

## M1 — Index, census and list (1 day)

`IntentsIndex` (apps and `/System/Library`, localized titles, host-app mapping, Team ID),
tiers, `census`, `list`, `doctor`.

**Accept:** `census` prints real counts by tier on this Mac; `list --json` validates;
tests pass.

## M2 — Enable and run (1 day)

`ShortcutForge`, signing, `enable`/`disable`, `Runner` (stdin redirected, timeouts,
read-back verification), `Store`.

**Accept:** enabling 5 simple actions through the CLI works end to end after the human
adds them and sets "Always Allow"; verified results where a read action exists.

## M3 — MCP server (1 day)

`serve` using the approach chosen in M0, tool schemas, destructive hints, call log.

**Accept:** in both Claude Code and Codex, a prompt such as "add a reminder to call the
dentist tomorrow at 10" creates the reminder, the result is verified by reading it back,
and the call appears in `intents-mcp log`.

## M4 — Packaging and launch prep (1–2 days)

Own Homebrew tap with a source-build formula (homebrew-core needs a 30-day-old repo and
225★ to self-submit). README with the real census numbers and the honest onboarding cost
(one "Add Shortcut" click and one "Always Allow" per tool). A 30-second demo video. MCP
Registry entry (MCPB bundle on GitHub Releases; see `05-distribution.md`). Fill in
`04-launch.md`. **GATE (human):** public repo, tap publishing, registry submission (GitHub
login), posting, Developer ID notarization only if shipping a prebuilt binary.

**Accept:** a clean Mac can install from the tap and pass the M3 check.
