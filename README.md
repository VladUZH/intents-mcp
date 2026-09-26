# intents-mcp

**Your Mac already ships over a thousand app actions. intents-mcp hands the ones you pick to
Claude Code, Codex or any MCP client, through Shortcuts, using public APIs only.**

```
$ intents-mcp census
This Mac declares 1,304 App Intents actions (1,249 unique)
in 224 metadata files, across 91 apps and system components.

  discoverable in Shortcuts  945
  simple tier                 47  background, plain inputs, returns output
  need an entity (a note…)   657  not supported yet
  …
```

<sub>Real output from the author's Mac (macOS 27.0, 2026-09-26). Run `intents-mcp census` to get yours.</sub>

Apps describe their actions for Siri and Shortcuts in App Intents metadata.
intents-mcp reads that metadata, lets you choose which actions an agent may use, wraps each one
in a small signed Shortcut, and serves them as MCP tools over stdio. When the agent calls a tool,
the Shortcut runs the app's action, and intents-mcp reads the result back where it can:

```
> Add a reminder to call the dentist tomorrow at 10.
reminders_add → {"ok": true, "output": "Call the dentist", "verified": true,
                 "detail": "read back through Shortcuts: due 26 Sep 2026 at 10:00"}
```

## What works today

Tools checked on real runs (macOS 27.0, Claude Code 2.1 and Codex 0.157):

| Tool | App | Read back |
|---|---|---|
| `reminders.add` | Reminders | yes (title, due date) |
| `calendar.create-event` | Calendar | yes (title, start) |
| `notes.create` | Notes | no |
| Writing Tools: Summarize, Proofread | Writing Tools | no |

Any action in the **simple tier** (runs in the background, plain text/number/date/choice
inputs, returns output) can be enabled from its metadata. Those tools are marked *not yet
checked on a real run*. In testing, 2 of 3 worked first time. The third (Notes "Create
Folder") never finished and was disabled, so check a new tool before relying on it.

## Install

```sh
brew install VladUZH/tap/intents-mcp     # prebuilt for Apple silicon; no dependencies
```

Intel Macs build from source, which needs Xcode.

No Homebrew yet? Its [installer](https://brew.sh) asks for your password, then waits for
RETURN, and can stay quiet for a few minutes while it downloads. That's normal. If you
already have Homebrew, run `brew update` first.

On macOS 27 this needs a current Homebrew (7.0 or later); older versions build from source
and ask for Xcode 27. Or from a clone: `swift build -c release` and use
`.build/release/intents-mcp`.
Needs macOS 26 or later (tested on 27.0) and the `shortcuts` command, which ships with macOS.

## Set up (about a minute per tool)

```sh
intents-mcp census                       # what your Mac has
intents-mcp list --tier simple           # checked tools first, then actions from metadata
intents-mcp enable reminders.add calendar.create-event
claude mcp add --scope user mac -- intents-mcp serve   # Claude Code, in every folder
codex mcp add mac -- intents-mcp serve                  # Codex
```

**The manual steps, honestly:**

1. `enable` opens each wrapper in Shortcuts. Click **Add Shortcut** once. Shortcuts has no
   public way to add a shortcut without that click.
2. The first time a tool runs, Shortcuts **may** ask for permission. Choose **Always
   Allow**. In testing, it asked every time data went into another app (Notes,
   CotEditor, MacWhisper), and mostly didn't for Reminders and Calendar. It can ask
   again after you upgrade a wrapper, because an upgraded wrapper is a new shortcut.

Tools that read their result back need a second **Add Shortcut** click: Reminders and
Calendar each add one small read-back helper ("intents-mcp verify.reminders" and
"intents-mcp verify.calendar"), shared by all tools of that app. Skip it and those tools
still run, but report "not verified".

Claude Code picks up enabled or disabled tools in a running session; other clients (e.g.
Codex) may need a restart.

## Privacy and safety

- **Runs on your Mac. Public APIs only.** It reads app metadata files, builds shortcuts,
  and runs them with Apple's `shortcuts` command. No private frameworks, no SIP or AMFI
  changes, no Accessibility clicking.
- **Signing involves Apple.** `shortcuts sign` uses your iCloud account, and Apple
  receives a copy of each wrapper for validation (Apple's Shortcuts guide says so). A
  signed wrapper also carries your Apple Account's signing identity (an account
  identifier and hashed email address and phone number), so intents-mcp deletes the
  signed file as soon as it sees the shortcut in your library (after `enable`, or on the
  next `enable`, `doctor`, `serve` or call of that tool). Don't share signed `.shortcut` files. Added
  shortcuts live in your Shortcuts library, which syncs through iCloud.
- **You choose every tool.** Nothing is exposed until you `enable` it. Actions whose
  names or descriptions suggest deleting, sending, buying or sharing are flagged and need
  `--allow-risky` (a broad word list, so some harmless ones are flagged too). Agents see them marked `destructiveHint`.
- **No telemetry, no network of its own.** The MCP server talks only to the client that
  started it, over stdio.
- **Every call is logged locally** (`intents-mcp log`): tool, time, duration, success,
  and whether it was verified, written when the call starts and when it ends, so an
  interrupted call still shows up. Arguments and results are not logged.
- **Results are read back** where a read action exists: the helper finds the item with the
  title just used and checks that it was created during the call. (If the app running your
  agent already has full Reminders or Calendar access, this is done with EventKit instead;
  see [PRIVACY.md](PRIVACY.md).) An older item with the
  same title, or a different item, reports `verified: false`, never a false success.
- **Unclear outcomes are said.** If a run times out or ends without a result, the tool
  says the action may still have happened (`outcomeUnknown`), so agents check before
  retrying. A call that never started (cancelled or out of time while queued) says so.

## Commands

```
intents-mcp census [--json]                   count the actions this Mac declares
intents-mcp list [--app <name>] [--tier simple|entity|unsupported|all] [--json]
                                              (--json: metadata actions only, with a status
                                              field; the checked tools are at the top of the
                                              text output)
intents-mcp enable <tool>... [--allow-risky]  make actions available to agents (alias or id)
intents-mcp disable <tool>...                 stop exposing them (alias or id)
intents-mcp call <tool> '<json args>'         run a tool as an agent would
intents-mcp tools                             the enabled tools
intents-mcp log [--last <n>]                  what agents called
intents-mcp doctor                            check this Mac is ready
intents-mcp serve                             MCP over stdio
```

In a terminal, the text output of `census`, `list`, `doctor`, `tools`, `log`, `enable` and
`disable` appears one line at a time: about 40 ms apart, adding at most 2 s to a command. Output
over 300 lines (such as a full `list`), pipes, files and `--json` print at once.
`INTENTS_MCP_LINE_DELAY_MS` sets the gap in milliseconds: `0` turns it off, and a larger value
such as `120` is slower, for a screen recording (it may then add up to 10 s to a command).
In a terminal, output also uses a few colors (green for what works, yellow for what needs you,
red for failures). Set `NO_COLOR=1` to turn them off; pipes, files and `--json` never get them.

## Limits

- **Entity actions aren't supported yet**, meaning actions that act on an existing note,
  reminder or list. On the author's Mac that's 657 of the 945 discoverable actions. A
  Shortcuts "Find" step that should pick one note once matched the wrong one in testing,
  so these stay off until they can be matched safely.
- **Declared is not the same as usable.** Some declared actions are refused by Shortcuts
  on the Mac, and some ignore their declared parameter names. Reminders and Calendar work
  through Shortcuts' built-in actions instead.
- **The CLI can't delete shortcuts.** After `disable`, delete the wrapper in the
  Shortcuts app yourself.
- **The Mac must be awake.** Shortcuts doesn't run while it's asleep. Another project reports runs working with the screen locked; that isn't tested here yet.
- **Few third-party apps ship App Intents yet.** On the author's Mac, 8 of 50 did.

## How it works

1. **Index.** It reads every `Metadata.appintents/extract.actionsdata` under
   `/Applications` and `/System`. No permission is needed. It maps each action to the
   app you know and sorts it into a tier.
2. **Wrap.** Each tool becomes one Shortcut: *JSON input → Get Dictionary Value per
   argument → the app's action → Get Text → Stop and Output.* It is signed with
   `shortcuts sign --mode people-who-know-me`.
3. **Run.** `shortcuts run <UUID> --input-path … --output-path …`, with stdin from
   `/dev/null` and a timeout. Arguments are checked first, because Shortcuts silently
   ignores keys it doesn't know.
4. **Serve.** A small MCP server over stdio: `initialize`, `tools/list`, `tools/call`.
   It works with Claude Code and with current Codex.

## License

MIT
