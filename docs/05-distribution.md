# 05 · Distribution plan for intents-mcp

Research date: **2026-09-25**. Every item below was checked on that date unless a row says otherwise. The research was read-only: nothing was posted, voted, starred, followed, signed up for or submitted, and nobody was contacted.

Launch line under test: *"Your Mac already ships about 600 agent tools. One command hands them to Claude or Codex, public APIs only."*
Success target (from `one-pager.html`): 1,000+ GitHub stars **or** 1,000+ Homebrew installs within 14 days.

## Method and limits

- **Tools used:** WebFetch, the HN Algolia and Firebase APIs, `gh api` (read-only), the public Mastodon and Bluesky APIs, Discourse `about.json`, Discord invite metadata, Wikidata, `formulae.brew.sh` analytics JSON, a headless browser for a few Reddit pages, and Wayback Machine captures.
- **The WebSearch quota ran out** (200 of 200) partway through. After that, sources were reached by direct URL and API. Some "not found" results below may exist but be unreachable without search.
- **x.com cannot be read by a machine** (HTTP 402, or only a JavaScript shell). X handles were verified indirectly: through GitHub `twitter_username`, the person's own site, Wikidata P2002, or HN links to `twitter.com/<handle>/status/…`. X follower counts are **unknown**.
- **Reddit:** see the Reddit section for which endpoints answered and which third-party numbers were used.
- **No invented numbers.** If a value was not read from a source, it says "unknown" or "unverified".

---

## 0. What the evidence says, in one screen

1. **Hacker News does not make Mac MCP tools popular.**
   - 27 HN submissions of Mac or Apple MCP servers have a **median of 3 points**. Only one passed 30 (Apple Health MCP, 199).
   - apple-mcp (3,127★) has no HN story at all.
   - Peekaboo (5,203★) scored 4 and 1 on HN; iMCP (1,653★) scored 10.
   - The closest competitor, Action Relay, got 3 points.
   - Stars in this niche came from **X/Bluesky, MacStories-style coverage and Reddit**. Treat HN as a lottery ticket, not the plan.
2. **What does score on HN is the story around it:**
   - "Agent Safehouse – macOS-native sandboxing" (823)
   - Cherri, which compiles to Apple Shortcuts (355)
   - the Safari MCP server (272)
   - "Setting up your spare Mac for Claude Code to control" (251)
   - "Siri AI can be swapped for Claude" (228)

   Lead with *safety* (public APIs, no SIP, user picks every tool) and *Shortcuts*, not with "MCP server".
3. **The Mac writers who matter have moved to Mastodon and Bluesky.** Viticci, Snell, Voorhees and Robles link only those on their MacStories and Relay pages. Viticci's Shortcuts Playground reached 1,126★ with a 3-point HN post, so the MacStories audience drove it.
4. **Homebrew target calibration:** `steipete/tap/peekaboo` logged **963 installs in 30 days** (formulae.brew.sh, 2026-08-26 to 09-25), with 5.2k★. "1,000 Homebrew installs in 14 days" would beat the best-known Mac agent tool's monthly tap installs. **Use stars as the primary target.** Also report GitHub release downloads, Homebrew tap installs and MCPB downloads.
5. **Directory gotchas:**
   - punkpeye/awesome-mcp-servers (95.5k★) requires a **Glama score badge**, and Glama's check starts the server from a Dockerfile. A macOS-only binary fails that unless the server builds and at least answers `tools/list` on Linux.
   - The official MCP Registry has **no Homebrew or raw-binary type**. Publish an **MCPB bundle** on GitHub Releases.
   - iCHAIT/awesome-macOS bans LLM/agent tools.
   - PulseMCP has paused submissions.
   - The Automators podcast ended in 2024.
   - Swift Weekly Brief stopped in 2022.
6. **homebrew-core is off the table for 14 days:** "A code repository less than 30 days old is normally not eligible". Self-submission also needs 90 forks, 90 watchers or 225 stars. Launch from your own tap. Since Homebrew 6.0.0, `brew install <user>/<tap>/intents-mcp` (fully qualified) is the one-line command that needs no extra `brew trust` step.
7. **Launch-blocking technical risk for "Claude *or Codex*":**
   - Codex CLI 0.154+ sends object-valued `experimental` capabilities.
   - The official Swift MCP SDK (0.12.1) fails `initialize` on them ([swift-sdk#287](https://github.com/modelcontextprotocol/swift-sdk/issues/287), open; fix PRs [#276](https://github.com/modelcontextprotocol/swift-sdk/pull/276) and [#289](https://github.com/modelcontextprotocol/swift-sdk/pull/289) open).
   - Test the launch build with current Codex before any post. See `tech-notes.md`.
8. **The "about 600" number needs to be re-stated as a measured count.**
   - The scan in `tech-notes.md` on this Mac found **942 discoverable App Intents actions**, **489 outside System Settings panes**, and 232 in Apple's apps plus Finder.
   - HN guidelines say to crop gratuitous numbers from titles anyway. Put the measured count, and the script that measures it, in the body.

---

## 1. Reddit

**How this was checked.**
- **Reddit blocks machine access.** `old.reddit.com/…/about.json` redirects to login, `www`/`api`/`oauth.reddit.com` return 403, and WebFetch refuses reddit.com.
- **Rules read first-hand, 2026-09-25:**
  - **r/macapps** and **r/shortcuts:** read in a headless browser before Reddit rate-limited it (HTTP 429).
  - **r/MacOS:** Wayback capture of 2026-08-07.
  - **r/macapps "Phase 3" rules post:** Wayback capture of 2026-07-25.
- **Member counts:**
  - **Reddit itself:** Reddit no longer shows a subreddit's own member count, but the r/macapps "Related communities" widget shows other subreddits' counts. Those were read live.
  - **Third party:** everything else comes from **reddapi.dev** (`https://reddapi.dev/subreddits/<name>/insights`), whose snapshot date is **unknown**. Where both exist, reddapi is 0.8–1.6% below Reddit's live number.
  - subredditstats.com was reachable but its data is stale.
- **Some reads were stopped by the session's permission checks** (archive APIs, further Wayback reads) and were **not** worked around.
- **"Rules unverified"** means the rules were not read today. No rule is stated that was not read.

### 1.1 Subreddits

| Subreddit | Members (source) | Self-promotion rule (as read) | Flair | Fit and format |
|---|---|---|---|---|
| **r/ClaudeAI** | 1,113,168 (reddapi) | Unverified. Description: "Anthropic does not control or operate this subreddit… Please read the rules before posting." | "Built with Claude" flair unverified | **High.** 30–60 s demo video plus the one-line install; say you are the author. |
| **r/ClaudeCode** | 402,454 (reddapi) | Unverified | Unknown | **High.** `claude mcp add --scope user mac -- intents-mcp serve` plus a clip of Claude creating a reminder. |
| **r/mcp** | 119,165 (reddapi) | Unverified | Unknown | **High.** Technical post: tool list, stdio transport, why a signed-shortcut wrapper (and not private XPC) is needed, known limits. |
| **r/shortcuts** | **572,352** (Reddit widget); 567,940 (reddapi). Reddit header: 163,100 weekly visitors, 2,399 weekly contributions | No self-promotion rule listed. Rule 1 "Stay related to Shortcuts"; Rule 10 "Don't Post Teasers"; Rule 11 "Crossposts are automatically filtered for review"; Rule 3 media only on Imgur, Gfycat or Reddit; Rules 5 and 7: posts with the 'shortcut' flair must link via iCloud, RoutineHub or Shortcuty ([about](https://www.reddit.com/r/shortcuts/about/)) | Rule 8 "Use post flair properly". Flair list unknown | **High.** Frame it as Shortcuts content: "how a generated wrapper calls an App Intent". Include an iCloud link to one sample wrapper and Reddit-hosted screenshots. Post natively, not as a cross-post, and only once it's ready. |
| **r/macapps** | 246,805 (reddapi) | Rule 3: "not permitted more than once per developer in 30 days… ALWAYS disclose your relationship to your software." Rule 1: "10pt LOCAL Karma Required… App Devs: No main feed promotion unless you qualify + use PCP template… Open Source? Prefix title [OS]." Rule 8: non-qualifying devs "must limit promotion to the monthly megathread." Rule 5: no redirect or shortened URLs ([about](https://www.reddit.com/r/macapps/about/)) | Free | **High audience, strict gate.** The ["Phase 3" post](https://www.reddit.com/r/macapps/comments/1ryaeex/) (2026-03-19) defines three tiers. **Tier 1** needs a Mac App Store app, a GitHub repo with 1+ year of history and 100+ stars, or recognized-dev flair; a new repo does not qualify. **Tier 2** needs a real identity (LinkedIn ideal) and a website with a Privacy Policy and ToS. **Tier 3** is the monthly "App Pile" megathread. Format: title `[OS] …`, PCP body (Problem, Comparison with 1–2 competitors, Pricing). The same post warns: "AI assisted comments are a huge trigger for Reddit auto-removals… (e.g. '—' em dashes)." |
| **r/MacOS** | **640,625** (Reddit widget); 630,310 (reddapi) | Rule 7: "Self-promotion is permitted only on Saturdays (UTC). This is limited to apps available on the official Mac App Store or reputable, established GitHub repositories. All GitHub links are subject to automated security auditing via GitHub-Guard." The sidebar says the sub uses a domain whitelist (Wayback 2026-08-07 of `old.reddit.com/r/MacOS/about/rules/`) | Unknown | **Medium.** Saturday (UTC) only. A brand-new repo may not count as "established". Link GitHub directly. |
| r/codex | 182,842 (reddapi). Unofficial; "information and discussion subreddit for OpenAI Codex tools - Codex CLI…" | Unverified | Unknown | **Medium–high.** `codex mcp add …` snippet, but only once Codex compatibility is verified (see 0.7). |
| r/iOSProgramming | 204,491 (reddapi). Description invites "open source projects… macOS" | Unverified | Unknown | Medium. A technical write-up of the `extract.actionsdata` format. |
| r/swift | 142,070 (reddapi) | Unverified | Unknown | Medium. The Swift implementation angle. |
| r/commandline | 131,089 (reddapi). Welcomes "console applications you've found or made yourself" | Unverified | Unknown | Medium. Terminal GIF plus the `brew install` line. |
| r/AI_Agents | 432,179 (reddapi) | Unverified | Unknown | Medium |
| r/ChatGPTCoding | 397,757 (reddapi) | Unverified | Unknown | Medium |
| r/SideProject | 828,438 (reddapi). "sharing and receiving constructive feedback on side projects" | Unverified | Unknown | Medium. Ask for feedback. |
| r/coolgithubprojects | 117,175 (reddapi) | Unverified | Unknown | Medium. Link post to the repo. |
| r/modelcontextprotocol | 23,776 (reddapi) | Unverified | Unknown | Medium (small) |
| r/opensource | 379,952 (reddapi) | Unverified | Unknown | Medium–low |
| r/Anthropic | 205,224 (reddapi) | Unverified | Unknown | Medium–low |
| r/automation | 230,275 (reddapi) | Unverified | Unknown | Medium–low |
| r/cursor | 155,563 (reddapi) | Unverified | Unknown | Low–medium (Cursor is an MCP client) |
| r/vibecoding | 349,412 (reddapi) | Unverified | Unknown | Low–medium |
| r/mac | **3,059,749** (Reddit widget) | Unverified | Unknown | Low–medium (consumer audience) |
| r/apple | **6,475,734** (Reddit widget) | Unverified (self-promotion ban **not verified**) | Unknown | **Low** (news and discussion) |
| r/OpenAI | 2,846,606 (reddapi) | Unverified | Unknown | Low |
| r/LocalLLaMA | 816,957 (reddapi) | Unverified | Unknown | **Low**, unless framed around a local MCP client or model |
| r/selfhosted | 832,208 (reddapi). "self-hosted alternatives to… web apps" | Unverified | Unknown | **Low** (not a web service) |
| r/SwiftUI | 63,456 (reddapi). "Please keep content related to SwiftUI only." | — | — | **Off-topic** (a CLI) |
| r/MacOSBeta | 55,535 (reddapi) | Unverified | Unknown | Low |

### 1.2 Comparable Reddit posts

**Unknown.** No Reddit launch post for apple-mcp, Peekaboo, macos-automator-mcp, the Shortcuts MCP servers or Shortcuts Playground could be read today:
- Reddit search was blocked.
- The WebSearch quota was exhausted.
- Archive routes were refused by the session's permission checks.
- None of those projects' READMEs links to a Reddit post.

The only score read was for a non-launch: the r/macapps "Mods Went Too Far! What's Changing (Phase 3)" post had 135 points (95% upvoted) at the Wayback capture of 2026-07-25.

**Human step:** before launch, search Reddit by hand for "apple-mcp", "Peekaboo", "shortcuts mcp", "macos automator" and "App Intents MCP" in r/ClaudeAI, r/mcp, r/macapps and r/shortcuts. Record 2–3 posts with their upvotes to calibrate.

### 1.3 What works on Reddit for this launch (from the rules read)

1. **Disclose authorship** in every post (r/macapps Rule 3).
2. **Write posts by hand**, one different post per subreddit. r/macapps warns that AI-looking text (em dashes) triggers auto-removal, and identical cross-posts trip spam filters. r/shortcuts filters cross-posts for review.
3. **Earn local karma first.** Build 10+ local karma in r/macapps, and ideally in r/shortcuts, by answering questions in the two weeks before launch.
4. **Choose the r/macapps path now.** Either qualify for Tier 2 (real identity plus a site with a Privacy Policy and ToS) or plan for the monthly App Pile megathread. Tier 1 needs 1+ year of repo history.
5. **Post r/MacOS on a Saturday (UTC)**, with a direct GitHub link. No redirects or shorteners anywhere.
6. **Space the posts out.** r/macapps allows one post per developer per 30 days, counted even if the post was removed.

---

## 2. Hacker News

### 2.1 Comparable posts (HN Algolia search, points re-checked on the HN Firebase API, 2026-09-25)

**Direct comparables**

| Title | Date | Points | Comments | URL |
|---|---|---|---|---|
| Show HN: Apple Health MCP Server | 2025-07-23 | 199 | 49 | https://news.ycombinator.com/item?id=44661673 |
| Show HN: Drive any macOS app in the background without stealing the cursor (Cua) | 2026-04-28 | 192 | 43 | https://news.ycombinator.com/item?id=47936312 |
| Show HN: Ableton Live MCP | 2026-05-03 | 123 | 79 | https://news.ycombinator.com/item?id=47999656 |
| Show HN: iMCP – Connect Your macOS Messages, Calendar, and More to Claude | 2025-03-06 | 10 | 6 | https://news.ycombinator.com/item?id=43281664 |
| Show HN: Cupertino – MCP server giving Claude offline Apple documentation | 2025-12-03 | 6 | 7 | https://news.ycombinator.com/item?id=46129111 |
| Show HN: Safari MCP – Native macOS browser automation (80 tools) | 2026-04-08 | 5 | 1 | https://news.ycombinator.com/item?id=47694855 |
| Give Your AI Agents Supernatural Vision on macOS (Peekaboo) | 2025-06-08 | 4 | 2 | https://news.ycombinator.com/item?id=44219988 |
| Apple working on MCP support to enable agentic AI on Mac, iPhone, and iPad (9to5Mac) | 2025-09-25 | 4 | 0 | https://news.ycombinator.com/item?id=45380248 |
| **Show HN: Action Relay – Every App Intent as an MCP Tool** (closest competitor; needs SIP off) | 2026-03-02 | 3 | 0 | https://news.ycombinator.com/item?id=47213940 |
| Shortcuts Playground: Create Apple Shortcuts with Claude Code/Codex | 2026-05-22 | 3 | 0 | https://news.ycombinator.com/item?id=48239460 |
| Show HN: MCP server that generates macOS tools via Open Scripting Architecture | 2026-03-31 | 2 | 2 | https://news.ycombinator.com/item?id=47594807 |
| MCP server to run AppleScript and JXA (macos-automator-mcp) | 2025-05-16 | 1 | 0 | https://news.ycombinator.com/item?id=44002337 |

**Nearby topics that did get traction**

| Title | Date | Points | Comments | URL |
|---|---|---|---|---|
| Agent Safehouse – macOS-native sandboxing for local agents | 2026-03-08 | 823 | 178 | https://news.ycombinator.com/item?id=47301085 |
| Cherri – programming language that compiles to an Apple Shortcut | 2026-03-27 | 355 | 74 | https://news.ycombinator.com/item?id=47549824 |
| The Safari MCP server for web developers (webkit.org) | 2026-07-03 | 272 | 76 | https://news.ycombinator.com/item?id=48769639 |
| Setting up your spare Mac for Claude Code to control | 2026-07-18 | 251 | 196 | https://news.ycombinator.com/item?id=48959392 |
| Apple's Siri AI Can Be Swapped Out for Claude, ChatGPT, Code Shows | 2026-09-14 | 228 | 162 | https://news.ycombinator.com/item?id=49695409 |
| The Sky's the limit: AI automation on Mac | 2025-06-04 | 123 | 71 | https://news.ycombinator.com/item?id=44179691 |
| Apple Shortcuts is falling into "the automation gap" (Six Colors) | 2025-05-05 | 111 | 79 | https://news.ycombinator.com/item?id=43892481 |
| Show HN: Use ChatGPT with Apple Shortcuts | 2023-09-27 | 54 | 45 | https://news.ycombinator.com/item?id=37671821 |

**Base rates**
- 27 Mac/Apple MCP submissions: median 3 points, mean 10.2, and 1 of 27 reached 30 or more.
- All Show HN posts from 2025-09-01 to 2026-09-17 (46,762, Algolia): median 2 points; 4.1% reached 30 or more; 1.7% reached 100 or more.

### 2.2 Rules that apply

- **[Show HN rules](https://news.ycombinator.com/showhn.html)**:
  - It must be "something you've made that other people can play with". Landing pages and sign-up pages don't qualify.
  - "Don't post quickly-generated one-offs."
  - Make it easy to try without sign-ups.
  - "Please don't ask friends to upvote or comment."
- **[Guidelines](https://news.ycombinator.com/newsguidelines.html)**:
  - Titles: no uppercase for emphasis, no exclamation points, and crop gratuitous numbers.
  - "Don't solicit upvotes, comments, or submissions."
  - "Please don't delete and repost."
  - **"Don't post generated text or AI-edited text."**
- **[dang's Show HN tips](https://news.ycombinator.com/item?id=22336638)** (edited 2026-03-28):
  - Write the text by hand, without LLM help "not even a tiny bit".
  - Give the backstory.
  - Link earlier related threads, which here means Action Relay 47213940 and iMCP 43281664.
  - Drop marketing language.
  - Don't use the project name as your username.
  - Put an email in your HN profile so moderators can invite a repost.
- **Reposts** ([FAQ](https://news.ycombinator.com/newsfaq.html); dang at [item 7992753](https://news.ycombinator.com/item?id=7992753)): if the first post gets no significant attention, a small number of reposts is fine. Use the [second-chance pool](https://news.ycombinator.com/pool); dang explains it at [item 26998308](https://news.ycombinator.com/item?id=26998308).

### 2.3 Draft titles (hand-edit before posting; all under 80 characters)

1. `Show HN: intents-mcp – Serve your Mac's App Intents as MCP tools` (64)
2. `Show HN: intents-mcp – A Swift CLI that turns App Intents into MCP tools` (72)
3. `Show HN: intents-mcp – Let Claude Code or Codex call macOS App Intents via MCP` (78)

Body checklist (write it yourself):
- what it does in one sentence;
- the measured count on your Mac and how to reproduce it;
- why signed shortcuts (public route, no SIP; contrast with Action Relay);
- the per-tool clicks (Add Shortcut, plus one for a read-back helper; sometimes Always Allow), stated honestly;
- what fails today (entity parameters, apps that open in the foreground);
- links to Action Relay and iMCP threads.

### 2.4 Timing

- **[Myriade](https://www.myriade.ai/blogs/when-is-it-the-best-time-to-post-on-show-hn)** (157k Show HN posts; success means 30+ points):
  - "Sunday: 11.75% breakout rate (BEST)"
  - "Golden window: 11:00-16:00 UTC"
  - "Avoid: 3:00-7:00 UTC"
- **[chanind](https://chanind.github.io/2019/05/07/best-time-to-submit-to-hacker-news.html)** (2018–2019 data): Sunday 06:00 UTC posts were 2.5× likelier to reach the front page than Wednesday 09:00 UTC, but weekends bring fewer total views.
- **Our own Algolia count** (46,762 Show HN posts from the last 12 months, share reaching 30+ points):
  - Sunday 4.86%, the best day.
  - 16:00–18:00 UTC at 5.3–5.6%, and 00:00 UTC at 5.4%, the best hours.
  - 03:00–08:00 UTC at 2.1–2.7%, the worst hours.
- **Recommendation:** **Sunday, 16:00–18:00 UTC** (09:00–11:00 PDT). Stay online for 3–4 hours to answer comments. Fallback: Tuesday to Thursday, same hours.

---

## 3. X (x.com)

x.com could not be fetched, so follower counts are unknown. The "Verified by" column says how each handle was confirmed. **Engagement rule for every row:** reply only when their post is on topic, with one concrete example; no cold @-mentions with links; no DMs.

| Handle | Who | Why engage | Verified by (checked 2026-09-25) |
|---|---|---|---|
| @viticci | Federico Viticci, MacStories | Built Shortcuts Playground (Claude Code/Codex writes shortcuts), the closest audience match | HN link to twitter.com/viticci (2017), https://news.ycombinator.com/item?id=15085159. Account exists; **current activity unverified**. His MacStories page lists only Mastodon and Bluesky |
| @macstoriesnet | MacStories | Covers App Intents, Siri AI, automation | Wikidata https://www.wikidata.org/wiki/Q123308619 |
| @jsnell | Jason Snell, Six Colors | Wrote "the automation gap" (111 HN points) | Wikidata https://www.wikidata.org/wiki/Q6163514. Much larger on Bluesky |
| @bleedsixcolors | Six Colors headlines | Headline feed | https://sixcolors.com/about/ |
| @gruber / @daringfireball | John Gruber | Links dev tools he likes | Wikidata https://www.wikidata.org/wiki/Q6236506; https://mastodon.social/@gruber |
| @mattcassinelli | Matthew Cassinelli | Former Workflow team; App Intents consultant; the Shortcuts expert | https://matthewcassinelli.com/ (links x.com/mattcassinelli) |
| @RosemaryOrchard | Rosemary Orchard | Automators co-host; Shortcuts and automation | https://api.github.com/users/RosemaryOrchard |
| @9to5mac | 9to5Mac | Broke the "Apple MCP in App Intents" story | https://www.wikidata.org/wiki/Q104055230 |
| @MacRumors | MacRumors | Ran the Siri AI / Claude swap story | https://www.wikidata.org/wiki/Q6722109 |
| @steipete | Peter Steinberger | Peekaboo (5.2k★), macos-automator-mcp | https://api.github.com/users/steipete; https://steipete.me/ |
| @dhravyashah | Dhravya Shah | apple-mcp (3.1k★) | https://api.github.com/users/Dhravya; https://dhravya.dev/ |
| @chris_tarquini | Christopher Tarquini | Action Relay; credit him as prior art | GitHub `twitter_username` of the Action Relay author: https://api.github.com/users/tarqd |
| @mattt | Mattt | iMCP (1.6k★); top contributor to the official Swift MCP SDK | https://api.github.com/users/mattt |
| @ai_mediar / @louis030195 | mediar-ai / Louis Beaumont | mcp-server-macos-use, screenpipe | https://api.github.com/users/mediar-ai; https://louis030195.com/ |
| @realtron | Neil Pullman | Apple Health MCP (199-point Show HN) | https://api.github.com/users/neiltron |
| @trycua | Cua | Background macOS agent driving (192-point Show HN) | https://api.github.com/users/trycua |
| @twostraws | Paul Hudson, Hacking with Swift | Swift community reach | https://api.github.com/users/twostraws |
| @twannl | Antoine van der Lee, SwiftLee | SwiftLee Weekly (31k+ subscribers) | https://api.github.com/users/AvdLee |
| @daveverwer | Dave Verwer | iOS Dev Weekly, Swift Package Index | https://daveverwer.com/ |
| @mecid | Majid Jabrayilov | Swift with Majid | https://api.github.com/users/mecid |
| @donnywals | Donny Wals | Swift writer | https://www.donnywals.com/ |
| @SwiftLang | Swift.org | Official | https://api.github.com/users/swiftlang |
| @dsp_ | David Soria Parra | MCP co-creator | https://api.github.com/users/dsp |
| @bcherny | Boris Cherny | Creator of Claude Code | Indirect: https://news.ycombinator.com/item?id=46470017 |
| @_catwu | Cat Wu | Claude Code product; MCP in Claude Code | Indirect: https://news.ycombinator.com/item?id=44311218 |
| @alexalbert__ | Alex Albert | Claude Relations, Anthropic | https://api.github.com/users/alexalbertt |
| @AnthropicAI / @claudeai | Anthropic / Claude | Official | https://www.anthropic.com/ ; https://claude.com/ |
| @embirico | Alexander Embiricos | Codex product lead | https://api.github.com/users/embirico |
| @thsottiaux | Thibault Sottiaux | Codex lead | Indirect: https://news.ycombinator.com/item?id=48799614 |
| @OpenAIDevs | OpenAI Developers | Codex official | https://developers.openai.com/codex |
| @simonw | Simon Willison | Writes about coding agents on macOS; no submissions taken | https://api.github.com/users/simonw |
| @swyx / @latentspacepod / @smol_ai | swyx, Latent Space, AINews | AINews picks items up from the AI Discords, Reddit and X | https://api.github.com/users/swyxio ; https://news.smol.ai/ |
| @bentossell | Ben Tossell, Ben's Bites | AI newsletter | https://www.bensbites.com/about |
| @tldrnewsletter | TLDR | No public submission form found | https://tldr.tech/ai |
| @therundownai / @rowancheung | The Rundown AI | Rowan's handle verified indirectly | https://www.therundown.ai/ ; https://news.ycombinator.com/item?id=38369677 |

**No X account verified for:** John Voorhees, David Sparks (MacSparky), Stephen Robles, Justin Spahr-Summers, Den Delimarsky (MCP lead maintainer), an official MCP account, Dominic-DK, Brandon Jordan (Cherri), the Jellycuts author, or iOS Dev Weekly as a brand.

**What kind of post works.** Sources: X's open-sourced ranking code, [xai-org/x-algorithm](https://github.com/xai-org/x-algorithm) `home-mixer/params/param.rs`, and X's rules via Wayback snapshots of [platform manipulation](https://web.archive.org/web/20241009034441/https://help.x.com/en/rules-and-policies/platform-manipulation) and [automation](https://web.archive.org/web/20260803124103/https://help.x.com/en/rules-and-policies/x-automation).
- **Ranking weights:** reply 5.0, quote 5.0, share via copy-link 20.0, like 0.5, repost 1.0, open link 0.2, "not interested" −43.2, report −234.
- **Replies are shown to non-followers only inside the thread.** `OONRetweetReplyFilter` removes replies from accounts the viewer does not follow.
- **Posts older than 48 hours are dropped** (`AgeFilter`).
- **Banned:** "bulk, aggressive, high-volume unsolicited replies, mentions" and "automated replies to posts based on keyword searches".
- **Recommended (opinion, based on the above):**
  - A native 20–40 s screen recording: `brew install` → pick Notes and Reminders → click "Add Shortcut" → Claude Code adds a reminder and appends to a note. Put the repo link in the first reply.
  - One on-topic reply under a relevant post from Viticci, steipete, Cat Wu or Boris.
  - A quote-post only when you add something new, such as a clip of the tool doing what their post describes.

---

## 4. Mastodon and Bluesky (where the Apple community is)

Verified through the public APIs (`/api/v1/accounts/lookup`, `app.bsky.actor.getProfile`). Follower counts are as the API returned them on 2026-09-25.

**Mastodon**

| Handle | Who | Followers |
|---|---|---|
| @gruber@mastodon.social | John Gruber | 58,030 |
| @viticci@mastodon.macstories.net | Federico Viticci | 33,248 |
| @simon@simonwillison.net | Simon Willison | 28,147 |
| @9to5Mac@mastodon.online | 9to5Mac | 26,273 |
| @macrumors@mastodon.social | MacRumors | 23,037 |
| @jsnell@zeppelin.flights | Jason Snell | 21,911 |
| @daringfireball@mastodon.social | Daring Fireball | 16,268 |
| @twostraws@mastodon.social | Paul Hudson | 11,766 |
| @macstories@mastodon.macstories.net | MacStories | 10,903 |
| @johnvoorhees@mastodon.macstories.net | John Voorhees | 10,171 |
| @sixcolors@zeppelin.flights | Six Colors | 7,666 |
| @steipete@mastodon.social | Peter Steinberger (last post 2026-04-11) | 4,675 |
| @swiftlang@mastodon.social | Swift.org | 4,012 |
| @rosemary@snailedit.social | Rosemary Orchard | 3,881 |
| @stephenrobles@mastodon.social | Stephen Robles | 3,288 |
| @daveverwer@mastodon.social | Dave Verwer | 3,168 |
| @macsparky@mastodon.social | MacSparky (probably David Sparks; not linked from his site) | 2,910 |
| @donnywals@chaos.social | Donny Wals | 2,422 |
| @relay@relayfm.social | Relay FM | 2,362 |
| @Mecid@mastodon.social | Majid | 1,957 |
| @dsp@nullptr.rehab | David Soria Parra | 208 |
| @localden@mastodon.social | Den Delimarsky | 117 |

**Bluesky**

| Handle | Who | Followers |
|---|---|---|
| snell.zone | Jason Snell | 98,609 |
| gruber.foo | John Gruber | 54,332 |
| simonwillison.net | Simon Willison | 50,390 |
| mackuba.eu | Kuba Suder (runs the "Mac & iOS Dev" feed) | 48,590 |
| 9to5mac.com | 9to5Mac | 31,478 |
| macrumors.bsky.social | MacRumors | 29,505 |
| viticci.macstories.net | Federico Viticci | 11,412 |
| swyx.io | swyx | 9,077 |
| johnvoorhees.macstories.net | John Voorhees | 6,825 |
| twostraws.bsky.social | Paul Hudson (self-described) | 6,544 |
| steipete.me | Peter Steinberger | 5,806 |
| stephenrobles.com | Stephen Robles | 5,614 |
| macstories.net | MacStories | 4,431 |
| sixcolors.com | Six Colors | 3,126 |
| swift.org | Swift | 3,060 |
| rosemaryorchard.com | Rosemary Orchard | 3,003 |
| matthewcassinelli.bsky.social | Matthew Cassinelli (runs a Shortcuts starter pack) | 2,986 |
| donnywals.bsky.social | Donny Wals | 2,319 |
| bcherny.bsky.social | Boris Cherny (verified badge) | 1,872 |
| daveverwer.com / iosdevweekly.com | Dave Verwer / iOS Dev Weekly | 1,769 / 723 |
| den.dev | Den Delimarsky | 1,656 |
| avanderlee.com | Antoine van der Lee | 1,444 |

Do not use `dsp.bsky.social` or `bensbites.bsky.social`: both belong to other people.

**Where to post**
- **Bluesky feeds:**
  - [Mac & iOS Dev](https://bsky.app/profile/mackuba.eu/feed/apple)
  - [macOS](https://bsky.app/profile/mackuba.eu/feed/mac)
  - [Swift Dev](https://bsky.app/profile/track.goodfeeds.co/feed/dd9c1d3aedd9)
  - [#Shortcuts](https://bsky.app/profile/gluebyte.bsky.social/feed/aaagrshlxpdwq)
  - [MCP Sky](https://bsky.app/profile/brianell.in/feed/mcp)
  - [Coding Agent](https://bsky.app/profile/ota.bsky.social/feed/aaajq3zke6euo)
- **Bluesky starter packs** to find people:
  - [Shortcuts (Cassinelli)](https://bsky.app/starter-pack/matthewcassinelli.bsky.social/3lb3opa4pzm2c)
  - [iOS and Mac developers](https://bsky.app/starter-pack/mackuba.eu/3l42zg45ofa2i)
  - [iOS Dev + AI](https://bsky.app/starter-pack/rudrank.bsky.social/3lc6skz6lgw2r)
- **Mastodon hashtag uses in the last 7 days on mastodon.social:** #macOS 431, #MCP 171, #ClaudeCode 134, #iOSDev 71, #Swift 71, #Shortcuts 14, #AppIntents 0.
  - Recommended tags: `#macOS #MCP #ClaudeCode #Shortcuts #Swift`.
  - A Swift developer server, iosdev.space, has 325 monthly active users.

---

## 5. Forums and communities

| Community | Where | Rules (short) | Size or signal | Fit |
|---|---|---|---|---|
| **Mac Power Users forum**, "Robot Assistant" category | https://talk.macpowerusers.com/c/robot-assistant/20 | The category invites people to "swap MCP configurations". A Feb 2026 staff thread ([t/44348](https://talk.macpowerusers.com/t/44348)) opposes drive-by promotion from new accounts. | 7,810 users; 766 active in the last 30 days | **High**, if you join the discussion |
| **MCP GitHub Discussions, "Show and tell"** | https://github.com/modelcontextprotocol/.github/discussions/categories/show-and-tell | "Show off something you've made." | 525 discussions | **High** |
| **Codex GitHub Discussions, "Show and tell"** | https://github.com/openai/codex/discussions/categories/show-and-tell | Same category type; a Mac tool was posted there on 2026-09-25 | 892 discussions | **Medium-high** |
| Swift Forums, Community Showcase | https://forums.swift.org/c/community-showcase/66 ([rules](https://forums.swift.org/t/40043)) | Bans "a program or library that's just written in Swift but doesn't provide a Swift programming interface". Allows "a developer tool that supports Swift". | 22,597 users; 1,471 active in the last 30 days | **Low–medium.** Only fits if framed as a Swift package, for example an `AppIntentsIndex` library or a tool that lets app developers test their own intents with agents |
| Apple Developer Forums (app-intents and shortcuts tags) | https://developer.apple.com/forums/tags/app-intents | "Avoid … solicitation, and self-promotion." ([guidelines](https://developer.apple.com/support/forums/)) | — | **Answer questions only**, and disclose that you wrote the tool |
| MacRumors forums, "Mac Apps and Mac App Store" | [developer guidelines](https://macrumors.zendesk.com/hc/en-us/articles/201294426-Guidelines-for-Software-Developers) | Promotion only in your own thread in the Software forums. Fill in "About you" (say you're a developer) and "Website". One thread per app or major release. | "exceeding 10000 forum posts per day" | Medium |
| Hacking with Swift forums, App Announcements | https://www.hackingwithswift.com/forums/app-announcements | "Just shipped a new app or a big update? Tell us about it!" | 100–300 views per post | Medium |
| OpenAI Developer Community | https://community.openai.com/c/codex/37 | "Share the cool things you have built, but avoid repetitive or overly promotional posts." ([FAQ](https://community.openai.com/faq)) | 1.03M users; 14,618 active in the last 30 days | Medium |
| Claude Discord (official) | https://www.anthropic.com/discord | Channel rules not visible without joining | 128,781 members | Medium |
| Glama MCP Discord (unofficial) | https://glama.ai/mcp/discord | Rules unverified | 14,173 members | Medium |
| Latent Space Discord | https://discord.gg/xJJMRaWCRt | Rules unverified. AINews summarizes it. | 13,327 members | Medium |
| Cline Discord, #mcp | https://discord.gg/cline | — | 23,623 members | Medium |
| Lobste.rs (invite only) | https://lobste.rs/about | Tags `show`, `mac`, `swift`. Self-promotion should be "less than a quarter of one's stories and comments". | — | Medium, if you have an invite |
| dev.to | https://dev.to/t/mcp , /t/showdev , /t/macos | Rules not reviewed | — | Medium–low; use it for a technical write-up |
| RoutineHub | https://routinehub.co/plugins/ | Now lists "AI Agent Plugins" (Claude Code plugins); account required | — | Medium, as a Claude Code plugin listing |
| Official MCP Contributors Discord | https://discord.gg/6CSzBmMkjX | "not intended for general MCP support"; no "product marketing" | 4,646 members | **Do not promote** |
| Automators forum | https://talk.automators.fm/c/shortcuts/14 | Standard Discourse rules | 5,081 users, but 75 active and 2 topics in the last 30 days. The podcast ended 2024-11-16 | Low (dormant) |
| MacStories Discord and Club | https://www.macstories.net/discord/ | Paid members only | — | Low. There is no public tips route; reach Viticci and Voorhees on Mastodon or Bluesky instead |
| Claude Code GitHub Discussions | — | Disabled on anthropics/claude-code | — | Not available |

---

## 6. Newsletters, podcasts and blogs

| Outlet | Submission route | Notes | Audience (source) | Fit |
|---|---|---|---|---|
| **iOS Dev Weekly** | https://suggest.iosdevweekly.com | Form allows "I wrote it!". Published Fridays (#768 on 2026-09-18). Owned by Mobile Seasons since May 2026. | "more than 40,000" ([about](https://iosdevweekly.com/about/)) | **High** |
| **Console.dev** | Email listed on https://console.dev/selection-criteria | 2–3 tools reviewed each week. Its **Betas** section accepts pre-1.0 developer tools; being macOS-only costs points. No paid reviews. Published Thursdays. | "30k+ subscribers" | **High** |
| **Changelog News** | https://changelog.com/news/submit (sign in) | "Submitting your own work is also encouraged." Published Mondays. | "26,711" | **High** |
| **Mac Power Users** (Relay) | https://relay.fm/mpu/feedback | Hosts David Sparks and Stephen Robles. Ep. 867 was a macOS 27 and Siri AI deep dive. | unknown | **High** |
| Connected (Relay) | https://relay.fm/connected/feedback | Includes Viticci | unknown | Medium |
| SwiftLee Weekly | No public route (email is hidden) | Published Tuesdays | "31,000+ subscribers … 59% open rate" ([sponsor page](https://www.avanderlee.com/sponsor/)) | Organic only |
| Fatbobman's Swift Weekly | "Contact Me" on https://fatbobman.com/en/about/ | Published Mondays | "5K+" (sponsor page) | Medium |
| Indie Dev Monday | Self-nomination per https://indiedevmonday.com/faq | Roughly every two weeks; last issue 2026-08-17 | unknown | Medium–low |
| 9to5Mac | https://9to5mac.com/contact/ (tips form) | "Submitting a tip constitutes permission to publish" | unknown | Low–medium |
| MacRumors | https://www.macrumors.com/share.php | Tip form | unknown | Low |
| AppleInsider | https://appleinsider.com/contact (tip form) | — | unknown | Low |
| MacStories / MacStories Weekly | **No public route.** The Weekly is members-only; no tips page (`/contact` and `/tips` return 404). | Reach them through Mastodon and Bluesky, or through Relay's Connected feedback form | unknown | High audience, organic only |
| Six Colors, Daring Fireball, Michael Tsai, Simon Willison | No submission routes. Simon: "I do not receive any compensation for writing about specific topics." Daring Fireball has a general contact page only. | — | — | Organic only |
| Latent Space / AINews | None. AINews auto-summarizes Discords, Reddit and X. | Being discussed in the Latent Space Discord or on r/LocalLLaMA and similar is the route | "over 150k" (news.smol.ai) | Medium, indirect |
| Hacker Newsletter | Picks from HN only | — | "60,000+" | Only if HN works |
| PulseMCP newsletter | None | Every two weeks; next issue listed for 2026-10-05 | unknown | Medium, indirect |
| TLDR AI, Ben's Bites, The Rundown, Pointer | Paid placements only; no editorial submission route found | — | TLDR AI 1.1M; Ben's Bites 171k; The Rundown 2M+ | Low |
| **Dead:** Automators podcast (ended 2024-11-16); Swift Weekly Brief (last issue 2022-06-22) | — | — | — | — |

---

## 7. Directories, registries and Homebrew

### 7.1 Where to list

| Directory | Route | Requirements | Qualifies? |
|---|---|---|---|
| **Official MCP Registry** ([repo](https://github.com/modelcontextprotocol/registry)) | `mcp-publisher` CLI, steps in 7.2 | **Preview** status ("Breaking changes or data resets may occur"). Package types: npm, PyPI, NuGet, Cargo, OCI, **MCPB** (GitHub or GitLab releases only). **No Homebrew type.** Namespace `io.github.<user>/…` via GitHub login; description ≤100 characters. | **Yes, via MCPB** |
| **Smithery** | https://smithery.ai/new or `smithery mcp publish ./server.mcpb` | Has a "Local (MCPB Bundle)" option for stdio servers ([docs](https://smithery.ai/docs/build/publish.md)) | Yes, via MCPB |
| **Claude Connectors Directory** (desktop extensions) | MCPB form linked from https://claude.com/docs/connectors/building/submission.md | Every tool needs a `title` and `readOnlyHint` or `destructiveHint`. Read and write must be separate tools. Privacy policy required in the README and in `privacy_policies`. Rule: "must call your own first-party APIs, or APIs you legitimately proxy" (**may conflict** with driving other apps' intents). Listed as "Community". | Yes via MCPB, but the ownership rule is uncertain |
| **Claude plugin directory** (Claude Code) | https://platform.claude.com/plugins/submit | Public GitHub repo; must pass `claude plugin validate`; local MCP servers allowed ([docs](https://claude.com/docs/plugins/submit.md)) | Yes |
| **punkpeye/awesome-mcp-servers** (95,510★) | PR, one line, "OS Automation" section, emojis 🏠 🍎 | CI bot (`check-glama.yml`) requires a **Glama score badge**. Glama must start the server from a Dockerfile and get answers to introspection. | **Only if** a Linux build starts and lists tools |
| Glama | https://glama.ai/mcp/servers → Add Server (login) | Automated license, security and health checks; `glama.json` in the repo | Same Linux caveat |
| wong2/awesome-mcp-servers (4,324★) | https://mcpservers.org/submit | "We do not accept PRs." Free review within 2 weeks, or $39 for 24 hours. | Yes |
| hesreallyhim/awesome-claude-code (54,591★) | Issue form `recommend-resource.yml`, filed by a human | Repo **≥14 days old** with commits after day 1, or ≥100★ | Yes, from day 15 |
| jaywcjlove/awesome-mac (114,828★) | PR | One item per PR, AP title case, alphabetical, OSS icon. Keep the 4 language READMEs in sync. Has an "AI Tools" section. | Yes |
| serhii-londar/open-source-mac-os-apps (50,554★) | PR to `applications.json` | Must build with current Xcode; English README | Yes ("Development") |
| mcp.so | https://mcp.so/submit?type=server | Repo URL; $39 for immediate listing | Yes |
| MCP Market | https://mcpmarket.com/submit | Free queue takes 4–6 weeks; $29 for 24 hours | Yes |
| LobeHub | `lhm plugin init --stdio …` then `lhm plugin publish` | LobeHub account plus GitHub push access; tools are captured by running the server locally | Yes |
| Cline MCP Marketplace | https://github.com/cline/mcp-marketplace/issues/new?template=mcp-server-submission.yml | 400×400 PNG logo; an `llms-install.md` helps. Backlog of 2,323 open issues. | Yes |
| PulseMCP | https://www.pulsemcp.com/submit | **Paused** (since 2026-09-03). Will import from the Official Registry later. | Not now |
| Docker MCP Catalog | PR to docker/mcp-registry | Needs a Linux container | **No** |
| OpenAI plugin directory | https://platform.openai.com/plugins | Needs a remote HTTPS MCP server | **No** |
| iCHAIT/awesome-macOS | — | Bans "software whose main purpose is interfacing with … LLMs … including agents" | **No** |
| appcypher/awesome-mcp-servers, herrbischoff/awesome-macos-command-line | — | Archived | No |
| Product Hunt | https://www.producthunt.com/launch | Launch at "12:01am PST". Personal accounts only. Co-makers should sign up "well before launch day". "You cannot ask people directly to upvote." Tagline ≤60 characters, description ≤500, 240×240 thumbnail, ≥2 gallery images. | Yes. No official data on how developer or OSS tools perform |

### 7.2 Publishing to the official MCP Registry (Swift binary)

Sources: registry repo docs (`quickstart.mdx`, `package-types.mdx`, `authentication.mdx`), schema `2025-12-11/server.schema.json`, and the MCPB `MANIFEST.md` and `calculator-rust` example. Checked 2026-09-25.

1. Build a release binary, universal if you want both architectures: `swift build -c release --arch arm64 --arch x86_64`.
2. Make an MCPB folder containing `manifest.json` and `server/intents-mcp`. The manifest needs:
   - `"manifest_version": "0.3"`
   - `"server": {"type": "binary", "entry_point": "server/intents-mcp", "mcp_config": {"command": "${__dirname}/server/intents-mcp", "args": ["serve"]}}`
   - `"compatibility": {"platforms": ["darwin"]}`
   - Add `privacy_policies` and tool annotations if you also want the Claude directory.
3. Package it: `npm i -g @anthropic-ai/mcpb`, then `mcpb validate manifest.json`, then `mcpb pack . intents-mcp-<v>.mcpb`.
4. Attach the `.mcpb` to a GitHub Release. The URL must contain "mcp"; the repo name `intents-mcp` satisfies that. Record the file's SHA-256.
5. `brew install mcp-publisher`, then `mcp-publisher init`. In `server.json`:
   - `"name": "io.github.<user>/intents-mcp"`
   - `packages: [{"registryType": "mcpb", "identifier": "<release URL>", "fileSha256": "<hex>", "transport": {"type": "stdio"}}]`
6. Run `mcp-publisher validate`, then `mcp-publisher login github` (**human step:** a device code entered at github.com), then `mcp-publisher publish`.
7. Verify with `curl "https://registry.modelcontextprotocol.io/v0.1/servers?search=io.github.<user>/intents-mcp"`.
8. Each version is immutable, so every change gets a new version string. CI can use `mcp-publisher login github-oidc`.

**Open questions**
- Whether Claude Desktop will run a binary from an MCPB that is not notarized. See `tech-notes.md` §7; signing it is safer.
- Whether downstream aggregators import entries that are MCPB-only.

### 7.3 Homebrew: own tap now, homebrew-core later

- **homebrew-core notability** ([Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy), read 2026-09-25):
  - "at least 30 forks, 30 watchers or 75 stars."
  - "at least 90 forks, 90 watchers or 225 stars for a self-submission by the repository owner."
  - "A code repository less than 30 days old is normally not eligible."
  - The formula must build from source with a stable tag and must not self-update ([Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae)).
- **Own tap:** `brew tap-new <user>/homebrew-tap` creates the GitHub Actions bottling workflow ([docs](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)).
  - Users run `brew install <user>/tap/intents-mcp`.
  - Since **Homebrew 6.0.0**, non-official taps need explicit trust. A **fully qualified install trusts only that formula**, so no extra step is needed. `brew tap` followed by a short-name install needs `brew trust --formula …` ([Tap Trust](https://docs.brew.sh/Tap-Trust)).
  - Always publish the fully qualified one-liner.
- **Install counts are public for taps too.** Analytics include "non-private GitHub tap names" ([Analytics](https://docs.brew.sh/Analytics)); see `https://formulae.brew.sh/api/analytics/install/30d.json`. Analytics are opt-out, so these counts undercount. 30-day benchmarks (2026-08-26 to 09-25):

  | Formula | Installs |
  |---|---|
  | xcbeautify | 52,222 |
  | swiftlint | 29,030 |
  | mint | 19,808 |
  | swiftformat | 5,577 |
  | **steipete/tap/peekaboo** | **963** |
  | github-mcp-server | 486 |
  | mcp-publisher | 187 |
  | steipete/tap/mcporter | 162 |
  | getsentry/xcodebuildmcp/xcodebuildmcp | 145 |
  | electrikmilk/cherri/cherri | 15 |
  | epistates/tap/mcp-safari | 12 |

---

## 8. 14-day launch calendar

**Assumptions**
- Day 1 is a **Sunday**, the best Show HN day (§2.4). Example: Sunday **2026-10-11**. Every date shifts together.
- Times are UTC.
- Nothing here is posted automatically. Every post is written and sent by the human author.
- Lines marked **GATE** need a human account or login.

**Before the clock starts (T-14 to T-1)**
- **T-14: make the repo public quietly.**
  - Then awesome-claude-code's "≥14 days old" rule is met on Day 1.
  - homebrew-core's "30 days old" rule is met around Day 17.
  - Stars before launch are fine.
- **T-14 onward: build karma by hand.** Answer questions in r/macapps and r/shortcuts until you have 10+ local karma (r/macapps Rule 1).
- **T-14 onward: set up accounts. GATE.**
  - Add an email to your HN profile (dang's tips).
  - Create a Product Hunt account ("well before launch day").
  - Check that you're signed in on the Mac Power Users forum.
- **T-7: test the launch build against real clients.**
  - Claude Code, Claude Desktop and current Codex CLI. The Codex `experimental` capability bug, swift-sdk#287, is launch-blocking for "Claude *or Codex*".
  - A fresh macOS 27 user account, with and without iCloud sign-in (`tech-notes.md` §9).
  - Write down the per-tool onboarding cost you actually see: the "Add Shortcut" click plus the first foreground "Always Allow" run.
- **T-7: measure the headline number on a clean Mac** with the published script. Replace "about 600" with the measured figure.
- **T-5: record the demo.** 30–40 s, native video, no voice needed: `brew install <user>/tap/intents-mcp` → `intents-mcp list` → enable Notes and Reminders → Add clicks → Claude Code adds a reminder and appends to a note. Make a 15 s cut for X and Bluesky.
- **T-3: stage the distribution artifacts.**
  - Cut v0.1.0 with a bottle in your own tap.
  - Build the MCPB bundle and attach it to the GitHub Release.
  - Publish to the official MCP Registry with `mcp-publisher login github`. **GATE**
- **T-1: write every post by hand**, one per channel. No LLM text on HN (guideline) or Reddit (auto-removal).

**The 14 days**

| Day | Date (example) | Channel actions | Why that day |
|---|---|---|---|
| 1 | Sun 10-11 | **Show HN at 16:00–18:00 UTC**; answer comments for 3–4 h. At the same hour: 15 s video on Bluesky (Mac & iOS Dev feed audience), Mastodon (`#macOS #MCP #ClaudeCode #Shortcuts #Swift`) and X, with the repo link in the first reply. MCP GitHub Discussions "Show and tell". | Sunday is the best day and 16–18 UTC the best hours (§2.4) |
| 2 | Mon 10-12 | r/ClaudeAI (morning US) and r/mcp (a separate, technical post, several hours later). Submit to Console.dev (Betas; pre-1.0 fits) and Changelog News (publishes Mondays, so this targets next week). | Weekday Reddit traffic. Newsletter lead times |
| 3 | Tue 10-13 | r/ClaudeCode. Directory listings: Smithery (MCPB), mcp.so, MCP Market (free queue), mcpservers.org (wong2), LobeHub, Cline marketplace (logo and `llms-install.md`). If HN got under 10 points, consider the second-chance pool (§2.2); do not delete and repost. | Spreads the traffic out |
| 4 | Wed 10-14 | iOS Dev Weekly suggestion (published Fridays). r/iOSProgramming: technical write-up of the `extract.actionsdata` format and what was learned. Mac Power Users forum, "Robot Assistant": a post to discuss, not a drop-link. | A Wednesday submission can make Friday's issue |
| 5 | Thu 10-15 | **Fix-and-release day**: ship v0.1.1 from the issues so far. Reply to every issue. r/commandline (terminal GIF). | Fast follow-up shows the project is maintained |
| 6 | Fri 10-16 | Codex GitHub Discussions "Show and tell", r/codex and OpenAI Community (Codex): **only if Codex compatibility is confirmed**. Hacking with Swift forums, App Announcements. | |
| 7 | Sat 10-17 | **r/MacOS** (self-promotion allowed only on Saturdays UTC). **r/macapps**: the monthly App Pile megathread, or a main-feed `[OS]` PCP post if Tier 2 applies. Week-1 metrics review (§9). | r/MacOS Rule 7 |
| 8 | Sun 10-18 | **r/shortcuts**: native post framed as Shortcuts content, with an iCloud link to one sample wrapper. Bluesky/Mastodon thread: "what I learned about App Intents entity parameters" (content, not a pitch). | Weekend reading. Reuses the Day-4 write-up |
| 9 | Mon 10-19 | Optional **Product Hunt** launch at 00:01 PT (no data on how developer tools do there; "You cannot ask people directly to upvote"). Relay feedback forms: Mac Power Users and Connected. | PH runs on a 24 h Pacific-time cycle |
| 10 | Tue 10-20 | Tip forms: 9to5Mac and MacRumors (only if there is news, such as a new version or a milestone). Fatbobman's Swift Weekly contact. Indie Dev Monday self-nomination. | |
| 11 | Wed 10-21 | **Release v0.2**, driven by what users asked for, for example more intents or `find_*` entity tools. Changelog post on X, Bluesky and Mastodon, quoting user feedback. PRs to jaywcjlove/awesome-mac ("AI Tools") and serhii-londar/open-source-mac-os-apps. | A second news moment for the same audience |
| 12 | Thu 10-22 | r/SideProject and r/coolgithubprojects (feedback-oriented). awesome-claude-code issue form (the repo is over 14 days old). | |
| 13 | Fri 10-23 | Swift Forums Community Showcase, **only if** a reusable Swift package, such as an App Intents indexer library, has been extracted (category rule). punkpeye/awesome-mcp-servers PR **only if** Glama's Docker check passes (§7.1). | Channels with gates |
| 14 | Sat 10-24 | Final review against the target (§9). Decide: double down (plan a v0.3 or MacStories-angle content, homebrew-core submission after day 30 if ≥225★) or move on. | One-pager decision rule |

**Channels deliberately left out:**
- Apple Developer Forums: no self-promotion; answer questions only.
- The official MCP Contributors Discord: no product marketing.
- iCHAIT/awesome-macOS: bans agent tools.
- Docker MCP Catalog and the OpenAI plugin directory: they need Linux or remote servers.
- PulseMCP: submissions paused. The Automators podcast: ended.
- r/apple, r/selfhosted, r/SwiftUI: poor fit.

---

## 9. Metrics to watch

The tool itself has no telemetry (it is local-first), so every metric comes from public or owner-visible platform data.

| Metric | Where to read it | Cadence | Notes |
|---|---|---|---|
| GitHub stars, forks, watchers | `gh api repos/<user>/intents-mcp --jq '.stargazers_count,.forks_count,.subscribers_count'` | Daily snapshot, saved to a file | **Dated star history could not be read today.** `stargazers` with `star+json` returned 404, and GraphQL `starredAt` edges came back empty, so keep your own daily log. homebrew-core self-submission needs 90 forks, 90 watchers or 225★ |
| Views, unique visitors, clones, top referrers | GitHub traffic API: `repos/<user>/intents-mcp/traffic/views`, `/traffic/clones`, `/traffic/popular/referrers` (owner access) | **Daily. The API only covers "the last 14 days"** ([docs](https://docs.github.com/en/rest/metrics/traffic)) | Referrers show which channel worked: news.ycombinator.com, reddit.com, t.co, bsky.app, a newsletter |
| Homebrew installs | `https://formulae.brew.sh/api/analytics/install/30d.json` (tap formulae are included) | Daily | Analytics are opt-out, so this undercounts. Benchmark: `steipete/tap/peekaboo` had 963 installs in 30 days |
| Release and MCPB downloads | `gh api repos/<user>/intents-mcp/releases --jq '.[].assets[] \| [.name,.download_count]'` | Daily | Counts MCPB and Claude Desktop installs |
| Activation friction | GitHub issues and Discussions tagged `onboarding`: reports of "Couldn't find shortcut", stuck consent prompts, signing failures | Daily triage | Proxy for "installed but never worked" |
| HN | Points, comments and rank on the item page; Algolia API | Hourly on Day 1 | Base rate: median 3 points for Mac MCP launches |
| Reddit | Upvotes, upvote ratio and removal status per post | Twice daily for 48 h | A removal usually means a rule problem; read the modmail |
| Social | Reposts and quotes on Bluesky and Mastodon (APIs); X by hand | Daily | Quotes and replies count most in X's ranking |
| Coverage | Newsletter issues (iOS Dev Weekly, Console, Changelog), blog links | Weekly | |

**Decision thresholds**
- **Primary (one-pager):** 1,000+ stars in 14 days.
- **Homebrew:** treat 1,000 installs in 14 days as a stretch goal, not the main test. It is about double Peekaboo's rate (963 in 30 days).
- **Move on if:** stars stay well below target, **or** Apple announces native MCP for App Intents. Watch the WWDC27 keynote and the macOS 27.x beta notes.

---

## 10. Blocked or unverified (2026-09-25)

- **WebSearch** hit the session limit (200 of 200). Later lookups used direct URLs and APIs, so some channels may exist that were not found.
- **x.com:** WebFetch returned HTTP 402, and curl gets only a JavaScript shell. help.x.com returned 403, so Wayback snapshots were used. **No X follower counts.**
- **X handles not verified:** John Voorhees, David Sparks, Stephen Robles, Justin Spahr-Summers, Den Delimarsky, an official MCP account, Dominic-DK, Brandon Jordan (Cherri), the Jellycuts author, iOS Dev Weekly. Viticci's X account is evidenced only from 2017.
- **Reddit:**
  - Direct fetches were blocked.
  - Only r/macapps, r/shortcuts and (via Wayback) r/MacOS rules were read.
  - **Comparable Reddit posts: unknown.** This is a human step, see §1.2.
  - reddapi.dev's snapshot date is unknown.
- **Not reachable or not public:**
  - MacRumors forum pages (403; the rules came from their Zendesk help center).
  - AppleInsider and RoutineHub (Cloudflare; read in a browser).
  - LobeHub marketplace (403).
  - Glama "Add Server" (login required).
  - Discord channel rules for Claude, Latent Space and Glama (you must join to see them).
  - talk.automators.fm and marigold.page timing article (no response).
- **Not found:** public submission routes for MacStories, Six Colors, SwiftLee, TLDR, Ben's Bites, The Rundown, Simon Willison, MacSparky and Unwind. Something may exist behind JavaScript.
- **Unknown:**
  - How developer and open-source tools perform on Product Hunt.
  - Whether downstream aggregators import MCPB-only registry entries.
  - Whether Anthropic's "first-party APIs" rule would block a Claude Directory listing.
  - Whether Claude Desktop runs a non-notarized binary from an MCPB.
- **Side effect:** the research agents' headless browser wrote snapshot files to `/Users/vlpetrov/Documents/Programming/limatum/.playwright-mcp/`, an already-untracked folder. Nothing was posted, starred, voted or submitted.
