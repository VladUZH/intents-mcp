# 04 — Launch

Channel details (subreddits and rules, X/Mastodon/Bluesky accounts, Mac and Swift
forums, newsletters, MCP registries, 14-day calendar) are in `05-distribution.md`.

**Status (2026-09-26):** the repo is public, v0.1.x is on GitHub, the Homebrew tap (Apple silicon
bottle) and the MCP Registry. Nothing has been posted. Open GATEs are listed at the end.

## The finding is the launch

> "Your Mac already ships over a thousand app actions. One command hands the safe ones to
> Claude or Codex, public APIs only."

Research shows stories framed around safety and Shortcuts do well on HN (Agent Safehouse 823
points, Cherri 355), while plain Mac MCP launches have a median of 3 points. Also useful:
which popular third-party apps are "agent-ready" (ship intents) and which aren't.

**Hacker News bans AI-written posts and comments. Write the Show HN title, post and
replies yourself.** Reddit auto-removes text that reads as AI-written. The facts below are
material for your own words, not copy to paste.

## Fact sheet (every number measured, with its source)

**The numbers** (`intents-mcp census`, author's Mac, macOS 27.0 build 26A428, 2026-09-26):

| | |
|---|---|
| App Intents actions declared | **1,304** (1,249 unique) in 224 metadata files, 91 apps and system components |
| Discoverable in Shortcuts (and available on macOS) | **945** |
| Simple tier (background, plain inputs, returns output) | **47** |
| Need an entity (a note, a reminder) | 657: not supported yet |
| Flagged risky (delete/send/buy/share in names or descriptions) | 134 |
| Third-party apps with intents | 8 of 50 installed: Word, Excel, PowerPoint, Outlook, Teams, WhatsApp, MacWhisper, CotEditor (21 actions, none in the simple tier) |

Say which Mac the numbers come from, and invite readers to run `intents-mcp census`.
Don't use "about 600" (one-pager) or "942 usable" (research, other counting rules).

**What was checked end to end** (STATUS.md, M0–M3):
- Claude Code 2.1.282 and Codex 0.157.0 both called `reminders_add` from the prompt "Add a
  reminder to call the dentist tomorrow at 10". The reminder was created and read back
  ("due 26 Sep 2026 at 10:00") in about 1.5 s.
- Working tools: Reminders add, Calendar event, Notes create, Writing Tools
  Summarize/Proofread. Read-back works for Reminders and Calendar.
- A warm call takes about 0.3–1.5 s. A cold call takes about 1.5–6 s.

**How it stays on public APIs.** It reads metadata files (no permission needed), builds one
Shortcut per tool, signs it with Apple's `shortcuts sign`, and runs it with
`shortcuts run`. No private frameworks, no SIP or AMFI changes, no Accessibility clicking.
Contrast: Action Relay does the same indexing but calls a private XPC service, which needs
SIP and AMFI off.

**The honest costs and limits** (say them before commenters do):
- **Manual steps per tool:** "Add Shortcut" once, plus once for a read-back helper (Reminders
  and Calendar have one each). Shortcuts may also ask to "Always Allow" on
  the first run: it did every time data went into another app (Notes, CotEditor,
  MacWhisper), and mostly didn't for Reminders and Calendar (clean run 2026-09-26: one dialog
  in total, 3.2 s). Both can happen again after a wrapper upgrade (a new shortcut).
- **Signing uses iCloud, and Apple receives a copy for validation.** Never say "nothing
  leaves your Mac".
- **Entity actions are not supported yet.** A Shortcuts "Find" filter matched the wrong
  note in testing, so they stay off until matching is safe.
- **Declared is not the same as usable.** Reminders' own App Intent is refused at import
  on the Mac; Reminders and Calendar go through Shortcuts' built-in actions. Notes'
  Create Note ignores its declared `contents` key. Generated tools: 2 of 3 worked first
  time.
- **The CLI can't delete shortcuts, and the Mac must be awake.**

**Likely questions, with answers:**
- *Why not AppleScript?* Many apps have no AppleScript dictionary, and App Intents are what
  Apple builds for Siri and Shortcuts now. AppleScript fallback is on the "Later" list.
- *Why not call the intents directly?* There is no public API for that. The only route is
  private XPC, which needs SIP off.
- *Isn't Apple going to ship this?* Maybe: there is MCP groundwork in App Intents, and a
  private MCP client in macOS 27. Until they do, this is the public route.
- *Does it work with Claude Desktop?* Not tested yet. The MCPB bundle is built, but it
  likely needs notarization.
- *Is it safe to let an agent do this?* You pick every tool. Risky ones need a flag. Every
  call is logged locally, and results are read back.

## Title options (hand-edit; from 05-distribution §2.3)

1. `Show HN: intents-mcp – Serve your Mac's App Intents as MCP tools` (64)
2. `Show HN: intents-mcp – Let Claude Code or Codex call macOS App Intents via MCP` (78)
3. Safety-first framing (suggested by §0): lead the body with "public APIs only, no SIP,
   you pick every tool", and keep the count out of the title (HN guidelines).

## Assets

| Asset | State |
|---|---|
| README (hero census output, install, per-tool clicks, privacy, limits) | **Ready:** `README.md` |
| Privacy policy (needed by the Claude directory and the MCPB) | **Ready:** `PRIVACY.md` |
| Homebrew formula | **Published:** https://github.com/VladUZH/homebrew-tap (Apple silicon bottle built by CI). `packaging/homebrew/intents-mcp.rb` is the template each release copies there |
| MCPB bundle | **Released** with each GitHub release (`scripts/build-mcpb.sh`, universal binary, `mcpb validate` passes). Not signed or notarized |
| MCP Registry | **Published:** `io.github.VladUZH/intents-mcp` (`packaging/registry/server.json`; each release needs a new version and a `mcp-publisher login github`) |
| Demo video (35 s main, 15 s social, 10 s README GIF) | **To do (human):** script in `06-demo-video.md` |
| "Which Mac apps are agent-ready" write-up | **Material ready:** census `--json` plus the third-party list above |
| Social thread (X / Bluesky / Mastodon) | Write by hand. Hook: the census screenshot, then the dentist-reminder clip |

## Success measure (set before launch)

**1,000+ GitHub stars within 14 days** is the main target. Homebrew tap installs are
secondary; for scale, Peekaboo's tap did 963 installs in 30 days. Double down if the target
is reached. Reassess at once if Apple announces native MCP for App Intents.

## Before launch: not yet done

- **Re-import the read-back helpers** after upgrading: 0.1.3 changes their format (creation-date
  check). `intents-mcp doctor` flags old helpers; `intents-mcp enable reminders.add
  calendar.create-event` adds the new ones. Check live that a call reads back "verified".
- Claude Desktop: not tested (60 s request timeout; `serve` budgets 50 s per call). The MCPB is
  not notarized.
- A clean Mac or fresh user account (the VM couldn't sign into iCloud); the clean-slate run on
  the author's Mac (2026-09-26) passed.
- Intel Macs build from source (needs Xcode); only an Apple silicon bottle exists.

## Human steps (GATE)

1. Developer ID signing and notarization, if shipping the MCPB or any prebuilt binary
   ($99/year Apple Developer Program). Not needed for the Homebrew source build.
2. Each release: tag, GitHub release, tap PR (CI bottle) and a new MCP Registry version
   (`mcp-publisher login github` needs a device code each time). Repo, tap and registry entry
   exist since 2026-09-25.
3. Record the demo. Post by hand, following the calendar in `05-distribution.md`.
