# 06 — Demo video

**One recording, three cuts.** Record one master take (about 35 s), then cut:

| Cut | Length | Where | Format |
|---|---|---|---|
| **Main** | 30–35 s | r/ClaudeAI, r/ClaudeCode (native upload), README (below the fold), release notes | MP4, 16:9, 1920×1080, burned-in captions, no voice |
| **Social** | 15 s | X, Bluesky, Mastodon (day 1, repo link in the **first reply**, 05 §8) | Same MP4 trimmed. Captions carry it: feeds autoplay muted |
| **README hero** | 8–12 s loop | Top of README, under the headline | GIF or animated WebP ≤ 8 MB, about 1200 px wide. GitHub autoplays GIFs but not videos |

Optional: a terminal-only GIF (census → list → enable) for r/commandline.

Priority: the **15 s social cut** matters most (05 §0: stars in this niche come from
X/Bluesky/Reddit, not HN). Then the 35 s Reddit cut. The README GIF is the smallest effort.

**The plan's outline had a bug:** 05 §8 says "appends to a note". That's an entity action, which
v1 doesn't support, so the script uses what works today: a reminder (with read-back), a calendar
event in Codex, and the log.

## Script (main cut, about 35 s)

| Time | Screen | Caption (burned in, ≤ 7 words) |
|---|---|---|
| 0–3 s | Terminal: `intents-mcp census`. Cut the ~10 s scan; land on "This Mac declares **1,304** App Intents actions". Zoom on the number. | **Your Mac ships 1,304 app actions.** |
| 3–8 s | `intents-mcp enable reminders.add calendar.create-event` → the Shortcuts "Add Shortcut" sheet → click (cut the repeat clicks: each tool plus its read-back helper). | **You pick each tool. A click to add it.** |
| 8–10 s | `claude mcp add --scope user mac -- intents-mcp serve` (pasted). | **Public APIs only. No SIP changes.** |
| 10–21 s | **Split screen:** Claude Code on the left, Reminders on the right. Type *"Add a reminder to call the dentist tomorrow at 10"*. The tool call runs; "Call the dentist, Tomorrow 10:00" appears on the right; Claude's reply ends with "…verified". | **Claude uses the app's own action…** then **…and reads the result back.** |
| 21–29 s | Codex on the left, Calendar on the right: *"Put 'Demo review' on my calendar tomorrow 14:00–14:30"* → the event appears. | **Codex too.** |
| 29–32 s | `intents-mcp log` shows `reminders.add … verified mcp:claude-code` and `calendar.create-event … mcp:codex-mcp-client`. | **Every call logged, on your Mac.** |
| 32–35 s | End card: `brew install VladUZH/tap/intents-mcp` and `github.com/VladUZH/intents-mcp`. | (the card is the caption) |

**Social cut (15 s):** 0–2 s the census number (caption "Your Mac ships 1,304 app
actions."), 2–12 s the Claude Code → Reminders beat, 12–15 s the end card.

**README GIF (about 10 s, loop):** only the Claude Code → Reminders beat, from typing the prompt
to "verified". No end card: the README already has the install line.

## Recording checklist

- **Real run, dead time trimmed.** Cut waits such as the 10 s scan; never fake a result. If you
  show a speed-up, label it ("sped up").
- **Do "Always Allow" before recording** if you don't want the dialog in the 15 s cut. In the
  35 s cut, keeping a real dialog is fine and honest (README: Shortcuts may ask once per tool).
- **Privacy:** use a dedicated Reminders list and calendar with nothing personal in them. Turn on
  Do Not Disturb, hide other windows and the Dock, and keep your Apple Account name out of
  sheets.
- **Readable on a phone:** terminal font 20 pt or larger, windows about 1280×800, one dark theme
  everywhere, cursor highlight on.
- **Captions:** large, high contrast, one line, on screen for at least 1.5 s each. No music, or
  very quiet.
- **Tools:** macOS's ⌘⇧5 screen recording is enough. Screen Studio (paid) adds automatic zooms.
  Cut in iMovie or CapCut. Make the GIF with `ffmpeg` (palettegen) or Gifski.
- **Before recording:** `brew upgrade intents-mcp`, `intents-mcp doctor` all ✓, both tools
  enabled (the Codex beat needs `calendar.create-event`), and test the exact prompts once so
  the takes are clean.
