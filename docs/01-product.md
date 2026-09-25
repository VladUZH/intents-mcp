# 01 — Product

## Who it is for

Mac users who run AI agents (Claude Code, Codex, Claude Desktop, other MCP clients) and
want those agents to use their Mac apps: create notes and reminders, add calendar
events, file things, control apps. The demand is visible:
- Peekaboo has about 5.2k stars and apple-mcp about 3.1k.
- A shortcut generator built by Federico Viticci got about 1.1k stars through MacStories.
- An HN post on Claude driving a spare Mac got 251 points.
See `evidence-adoption-check.md`.

## The job

"Let my agent use my Mac apps properly: through the actions the apps officially offer,
not by clicking around the screen, and without turning off my Mac's security."

## What the user sees

1. `brew install …/intents-mcp`
2. `intents-mcp census`: "Your Mac has N actions in M apps that agents could use."
3. `intents-mcp list --app Notes`: the actions, their inputs, and a safety mark on risky
   ones.
4. `intents-mcp enable reminders.add calendar.create-event`: creates signed shortcuts; the
   user clicks "Add Shortcut" once for each, then runs each once and picks "Always
   Allow" (needed again after upgrades).
5. `claude mcp add mac -- intents-mcp serve`. Claude can now use those actions and gets
   their results back.
6. `intents-mcp log` shows what agents called.

## Why it can become popular

- A striking, true number from the user's own Mac is the hook. The Mac checked had 1,269
  actions, 942 usable in Shortcuts and 129 that run in the background with simple inputs;
  `census` produces the real numbers.
- It is the safe version of something people already want: public APIs only, the user
  picks every tool.
- Mac and Apple writers (MacStories, Six Colors, 9to5Mac) and the MCP community are
  reachable audiences.
- It costs nothing to serve: it all runs on the user's Mac.
- It fits the founder: Swift, macOS, App Intents, and Limatum's Mac automation code.

## Risks (from the adoption check)

- **Apple may ship this itself.** MCP groundwork was found in App Intents betas, and OS 27
  lets Siri hand requests to ChatGPT or Claude. If Apple announces native MCP for App
  Intents, reassess at once.
- **Entity inputs.** 666 of the 942 usable actions take an entity (a note, a reminder),
  which Shortcuts won't accept as plain text. v1 may ship only the simple tier.
- Two manual steps per tool ("Add Shortcut", then "Always Allow"); keep the default set
  small and useful.
- Signing needs an iCloud login and Apple receives a copy of each shortcut.
- The Swift MCP SDK currently fails with Codex; see the spec.
- macOS 27 contains a private MCP client (`GenerativeAgents.framework`), another sign
  that Apple may build this itself.
- Few third-party apps ship intents today (8 of 50 apps on the Mac checked).

## Later (not in the weekend build)

iPhone support through Shortcuts; a small menu-bar app to enable tools and watch the
log; falling back to Limatum's Apple Events and Accessibility drivers (with read-back
checks) for apps without intents; a public "which Mac apps are agent-ready" index built
from census data volunteered by users.
