# 04 — Launch

Channel details (subreddits and rules, X/Mastodon/Bluesky accounts, Mac and Swift
forums, newsletters, MCP registries, 14-day calendar) are in `05-distribution.md`.

## The finding is the launch

> "Your Mac already ships over a thousand app actions. One command hands the safe ones to
> Claude or Codex, public APIs only."

Use the real `census` numbers (the Mac checked on 2026-09-25 had 1,269 actions, 942 usable
in Shortcuts, 129 in the simple tier), and say which Mac they come from. Research shows
stories framed around safety and Shortcuts do well on HN (Agent Safehouse 823 points,
Cherri 355), while plain Mac MCP launches have a median of 3 points. Also useful: which
popular third-party apps are "agent-ready" (ship intents) and which aren't.

**Hacker News bans AI-written posts and comments. Write the Show HN title, post and
replies yourself.**

## Assets to prepare (M4)

- README hero: the census number, `brew install`, a 30-second video.
- Show HN fact sheet (what, how it stays on public APIs, limits such as the two manual
  steps per tool, likely questions) for the founder to write the post by hand.
- A short write-up pitched to Mac writers: "which Mac apps are agent-ready".
- Reddit posts per subreddit, written to each one's rules.
- X/Mastodon/Bluesky thread with the video.
- MCP Registry and awesome-list submissions.

## Success measure (set before launch)

Suggested: **1,000+ GitHub stars within 14 days** as the main target. Homebrew tap installs
appear in public analytics, but for scale, Peekaboo's tap did 963 installs in 30 days, so
installs are a secondary signal. Double down if reached.
Reassess at once if Apple announces native MCP for App Intents.

## Human steps (GATE)

1. Developer ID signing and notarization, if shipping a binary.
2. Public repo, Homebrew tap, MCP Registry submission.
3. Post, following the calendar in `05-distribution.md`.
