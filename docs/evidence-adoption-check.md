# Check B: adoption signals for three shovel ideas (2026-09-25)

Question: could each idea become extremely popular with people building with AI, even if it is free at first? These ideas are judged on adoption, not on willingness to pay.

## Method and caveats

- Sources: WebSearch, WebFetch of primary pages, HN Algolia API, `gh api` / `gh search repos` (read only), the npm downloads API, and read-only inspection of app bundles on this Mac (macOS 27.0, build 26A428).
- **Star growth could not be dated.** On 2026-09-25 the REST endpoint `repos/OWNER/REPO/stargazers` returned HTTP 404 for every repo I tried, with or without the `star+json` header, and GraphQL `stargazers { totalCount }` returned 0. Where earlier notes in `research_notes/` hold a star count from 2026-09-22, I give the three-day change instead.
- Subreddit sizes come from reddapi.dev, a third-party mirror, because Reddit refuses direct fetches. The date of that snapshot is unknown, and Reddit stopped showing public member counts in September 2025.
- Where a number was not seen in a source, it is written as "unknown". Cost figures are estimates built from stated assumptions and list prices. They are not measurements.

---

## Idea 1 (id 53): a free local bridge from App Intents to MCP, plus an App Intents generator

### (a) Closest free and open-source projects, and how much they are used

| Project | What it does | Adoption |
|---|---|---|
| [tarqd/action-relay](https://github.com/tarqd/action-relay) ([write-up](https://tarq.net/posts/action-relay-shortcut-actions-mcp/)) | **The exact idea.** It reads each app's `Contents/Resources/Metadata.appintents/extract.actionsdata`, builds workflow plists in memory and sends them to WorkflowKit's `BackgroundShortcutRunner` XPC service. That needs the private entitlement `com.apple.shortcuts.background-running`, so **SIP and AMFI must be disabled**. It describes itself as a proof of concept. | 5★, 1 fork, created 2026-03-02, last push 2026-04-08. [Show HN](https://news.ycombinator.com/item?id=47213940): 3 points, 0 comments |
| [bradwindy/app-intents-mcp](https://github.com/bradwindy/app-intents-mcp) | Same idea. The README says "WORK IN PROGRESS: Not yet working". | 1★, created 2025-12-16 |
| [Dominic-DK/mac-shortcuts-mcp](https://github.com/Dominic-DK/mac-shortcuts-mcp) | Reads Calendar, Notes, Contacts and similar data through bundled shortcut "recipes" using only public tools. Setup signs each recipe with `shortcuts sign`, and **the user clicks "Add Shortcut" once per recipe** (an `--auto` flag clicks through Accessibility). It ships a catalog of 539 Shortcuts actions harvested from `WFActionRegistry`, and notes that "a wrong parameter key does not raise an error — it is silently ignored". | 14★, created 2026-09-19 |
| [viticci/shortcuts-playground-plugin](https://github.com/viticci/shortcuts-playground-plugin) ([MacStories](https://www.macstories.net/stories/introducing-shortcuts-playground/)) | A Claude Code / Codex plugin that generates, validates and signs shortcuts (about 2,000 actions and intents), from Federico Viticci. It is the nearest thing to the "generator" half. | **1,126★**, created 2026-04-14. The [HN post](https://news.ycombinator.com/item?id=48239460) got only 3 points, so the stars came through MacStories, not HN |
| [recursechat/mcp-server-apple-shortcuts](https://github.com/recursechat/mcp-server-apple-shortcuts) | Runs a user's existing shortcuts from MCP | 349★, created 2024-12-11, last push 2024-12-22 (stale) |
| [artemnovichkov/shortcuts-mcp-server](https://github.com/artemnovichkov/shortcuts-mcp-server), [foxtrottwist/shortcuts-mcp](https://github.com/foxtrottwist/shortcuts-mcp) | Run shortcuts from MCP | 32★ and 11★ |
| Adjacent: Mac control over MCP | [supermemoryai/apple-mcp](https://github.com/supermemoryai/apple-mcp), [openclaw/Peekaboo](https://github.com/openclaw/Peekaboo), [steipete/macos-automator-mcp](https://github.com/steipete/macos-automator-mcp) (archived), [mediar-ai/mcp-server-macos-use](https://github.com/mediar-ai/mcp-server-macos-use); for comparison, [CursorTouch/Windows-MCP](https://github.com/CursorTouch/Windows-MCP) | 3,127★ (last push 2025-08-11); 5,203★; 885★; 354★; 7,166★ |
| Adjacent: App Intents tooling | [n0an/App-Intents-Agent-Skill](https://github.com/n0an/App-Intents-Agent-Skill); [mpociot/claude-siri-ai](https://github.com/mpociot/claude-siri-ai) | 35★ (unchanged since 09-22); 220★ (218 on 09-22, so the launch spike has faded) |
| HN demand signal | ["Setting up your spare Mac for Claude Code to control"](https://news.ycombinator.com/item?id=48959392) (2026-07-18) | 251 points |

**Local measurement (this Mac only, so not representative).** I scanned for `Metadata.appintents/extract.actionsdata`:
- Third-party apps: only 8 of the 50 apps in `/Applications` ship App Intents, with **23 actions in total**. They are Microsoft Word, Excel, PowerPoint, Outlook and Teams, plus WhatsApp, MacWhisper and CotEditor.
- Apple's apps: `/System/Applications` has 47 metadata files with 289 actions (for example Notes 51, Books 28, Freeform 24, Mail 23, Preview 17).
- Apple's private frameworks: 52 files with 312 actions.
- In practice, "every installed app's intents" today means mostly Apple's own apps.

**Feasibility with public APIs.** No public API invokes another app's App Intent directly. There are two routes:
1. The private XPC route that Action Relay uses. It needs SIP turned off, so it cannot ship to normal users, and it would break the "public APIs only" rule.
2. Generate a wrapper shortcut, sign it with `shortcuts sign` (the subcommand is present on macOS 27; the others are `run`, `list` and `view`), have the user click "Add Shortcut", then call `shortcuts run`. The mac-shortcuts-mcp and Shortcuts Playground projects prove this route works. It costs **one confirmation click per exposed tool**, and entity parameters and silently ignored parameter keys make it fragile.

### (b) Communities that would spread it

- **Reddit** (reddapi.dev): r/ClaudeAI 1,113,168 members; r/shortcuts 567,940; r/macapps 246,805; r/mcp 119,165.
- **MacStories.** It delivered 1,126★ to Shortcuts Playground with almost no HN help.
- **MCP directories:** Smithery, mcp.so, LobeHub, and the Claude connectors directory, which lists 829 connectors according to `AI shovel opportunities/scan/new-surfaces--community-code.md`.
- **HN:** Shortcuts and MCP launches have scored 3 points each, but "Claude controls my Mac" content scores in the hundreds.

### (c) Cost to serve free users

Assumption: everything runs locally, the binaries ship through GitHub Releases or Homebrew (free), and the docs site sits on Cloudflare Pages (free plan).

| Free users | Marginal cost |
|---|---|
| 10k | ≈ $0/month, plus the Apple Developer Program at US$99/year for Developer ID signing and notarization |
| 100k | Same: ≈ $0/month plus US$99/year |

The real cost is support time (unknown).

### (d) Has Apple or anyone else shipped or announced it?

- **Apple has code for it.** [9to5Mac, 2025-09-22](https://9to5mac.com/2025/09/22/macos-tahoe-26-1-beta-1-mcp-integration/) found "very incipient MCP support" in App Intents in the 26.1 betas, meant to let ChatGPT or Claude act in apps "without requiring developers to implement full MCP support". I found no developer.apple.com documentation of it as of macOS 27 GA. A [Blake Crosley post (updated 2026-07-07)](https://blakecrosley.com/blog/app-intents-vs-mcp-tools-frontier) says: "Apple Intelligence does not call MCP tools, and external LLM agents cannot directly invoke App Intents".
- **Apple already ships MCP elsewhere.** It shipped MCP in the [Safari 27 MCP server](https://9to5mac.com/2026/09/17/webkit-blog-breaks-down-whats-new-with-safari-27-for-developers-including-mcp-support/) and in the Xcode 27 `mcpbridge`. Both are developer-facing.
- **Hidden Model Delegation / Siri Extensions.** Code in the OS lets Claude or ChatGPT receive "Apple's Siri planner prompt and tool definitions" ([MacRumors, 2026-09-14](https://www.macrumors.com/2026/09/14/siri-can-be-swapped-out-for-chatgpt-claude/); [HN 228 points](https://news.ycombinator.com/item?id=49695409)). It is not open to third parties. If Apple opens it, third-party models reach intents through Siri and the bridge is absorbed.
- **OpenAI** acquired Sky, whose founders came from Shortcuts/Workflow ([OpenAI, 2025-10-23](https://openai.com/index/openai-acquires-software-applications-incorporated/)).
- **Anthropic** shipped Claude computer use on Mac (2026-03-24, [VentureBeat](https://venturebeat.com/technology/anthropics-claude-can-now-control-your-mac-escalating-the-fight-to-build-ai)).

### (e) The weekend version, and what its launch post would say

**`intents-mcp`**, a Swift CLI and MCP server:
- It indexes every `extract.actionsdata` on the Mac and serves the catalog as MCP tools and resources.
- For each tool the user enables, it generates and signs a wrapper shortcut (one "Add" click), then runs it with `shortcuts run`.
- It uses public APIs only: no SIP changes and no Accessibility permission.

**Launch post:** "Your Mac already ships ~600 agent tools, built by Apple for Siri. One command hands them to Claude Code, Codex or any MCP client. Public APIs only, nothing leaves your Mac." Demo GIF: Claude searches Mail, creates a Freeform board and appends to a Note through intents.

### (f) Verdict: adoption evidence **medium**

**Biggest reason:** demand next to this idea is proven (Shortcuts Playground 1,126★ in 5 months, apple-mcp 3.1k★, Peekaboo 5.2k★). But the exact bridge hits a public-API wall: one click per tool, and very few third-party apps ship intents (23 actions on this Mac). Apple has also had MCP-in-App-Intents code in the OS since 26.1, so the Sherlock risk is high.

---

## Idea 2 (id 214): a SwiftUI-in-the-browser preview renderer

### (a) Closest free and open-source projects, and how much they are used

| Project | What it does | Adoption |
|---|---|---|
| [MiniSwift](https://miniswift.run/) / [toprakdeviren/msf](https://github.com/toprakdeviren/msf) | **Already does the idea for free.** "Write and run SwiftUI in any browser" with no Mac, Xcode or server. A Swift compiler pipeline, SwiftUI runtime and Foundation bridge are written from scratch in C and run as Wasm. It has live preview, a debugger, offline use and an embed option. Only the frontend is open source. | msf 316★ (312 in earlier notes), created 2026-04-07. HN [2 points](https://news.ycombinator.com/item?id=48290888) (2026-05-27) and [2 points](https://news.ycombinator.com/item?id=48498374) (2026-06-12). Usage: unknown |
| [iamcgn/swiftui-web](https://github.com/iamcgn/swiftui-web) (SwiftUIWeb, Apache-2.0) | Runs unmodified SwiftUI and UIKit source on Wasm and Canvas, checked against goldens rendered by Apple's SwiftUI. Of 187 rows in its support matrix, 20 are full, 154 partial, 5 approximate, 5 stubs and 3 missing. `#Preview` is a stub. SF Symbols are replaced by Lucide icons. **There is no in-browser compiler**; it needs swiftc plus the Wasm SDK. | 0★, created 2026-09-04, active |
| [TokamakUI/Tokamak](https://github.com/TokamakUI/Tokamak) | A SwiftUI-compatible framework for the browser | 2,837★, **archived**, last push 2024-03-23. Best HN result: 6 points |
| [OpenSwiftUIProject/OpenSwiftUI](https://github.com/OpenSwiftUIProject/OpenSwiftUI) | Open-source reimplementation of SwiftUI (not browser-first) | 2,468★, active |
| [elementary-swift/elementary-ui](https://github.com/elementary-swift/elementary-ui) | A SwiftUI-*style* browser framework that cannot run SwiftUI source unchanged | 501★ |
| Toolchain: [swiftwasm/swift](https://github.com/swiftwasm/swift), [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit) | Official WebAssembly support since Swift 6.2 ([swift.org Goodnotes post, 2026-06-01](https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/); Goodnotes' Wasm bundle is 12 MB after Brotli) | 1,389★ and 986★. The 2019 SwiftWasm launch got [187 HN points](https://news.ycombinator.com/item?id=19880464) |
| [SwiftFiddle](https://github.com/SwiftFiddle/swiftfiddle-web) | Online Swift playground that compiles on a server | 275★ |
| [Bitrig](https://bitrig.com/blog/swift-interpreter) (YC S25) | A Swift-in-Swift interpreter on iPhone that calls the real SwiftUI, for instant previews shared by URL | Commercial |
| [k-kohey/axe](https://github.com/k-kohey/axe) | SwiftUI preview CLI and VS Code extension (Mac only) | 91★ |

**Feasibility.** Rendering is largely solved in open source. The blocker is compiling user code:
- **In the browser:** MiniSwift wrote its own compiler to do this. I found no working build of swiftc that runs in the browser.
- **On a server:** this adds cost and sandboxing for arbitrary code.
- **Fidelity has a ceiling:** SF fonts and SF Symbols cannot legally ship.

### (b) Communities that would spread it

- **Reddit** (reddapi.dev): r/vibecoding 349,412; r/iOSProgramming 204,491; r/swift 142,070; r/SwiftUI 63,456.
- **Other channels:** Swift Forums, Hacking with Swift readers, Swift Student Challenge entrants (size unknown).
- **HN track record:** every SwiftUI-in-browser launch since 2020 scored 6 points or fewer. The only exception is the SwiftWasm toolchain in 2019, with 187.

### (c) Cost to serve free users

**Route A: compile client-side (the MiniSwift model).**
- Assumptions: a 10–15 MB Wasm bundle (Goodnotes' 12 MB Brotli as the reference) and 3 cold loads per user per month.
- Traffic: 10k users ≈ 300–450 GB/month; 100k users ≈ 3–4.5 TB/month.
- Price: [R2 egress is free](https://developers.cloudflare.com/r2/pricing/), storage is $0.015/GB-month, and Class B reads are $0.36 per million after 10M free.
- Result: **≈ $0–10/month** at either scale.

**Route B: compile on a server (the SwiftUIWeb model).**
- Assumptions (not measured): 5 CPU-seconds per compile and 50 previews per user per month.

| Free users | Compiles/month | CPU-hours | Pure compute on [Fly performance-2x](https://docs.fly.io/about/pricing/) (2 vCPU, 4 GB, $0.0894/hr) |
|---|---|---|---|
| 10k | 500k | ≈ 694 | ≈ $31/month |
| 100k | 5M | ≈ 6,944 | ≈ $310/month |

Peak headroom and sandbox isolation plausibly multiply this by 3–10×, giving roughly **$100–300/month at 10k and $1k–3k/month at 100k**.

### (d) Has Apple or anyone else shipped or announced it?

- **Apple:** Xcode 27 adds previews for standalone Swift files, untitled projects, and preview rendering exposed to external agents through the MCP bridge ([WWDC26 SwiftUI guide](https://developer.apple.com/wwdc26/guides/swiftui/); [Xcode 27 session 258 summary](https://wwdc.ai/2026/258)). All of it is Mac-only. Nothing has been announced for the web or Linux.
- **Funded startups** already solve previews for AI builders:
  - Rork: $15M seed, streams a cloud simulator.
  - Bitrig (YC S25): interpreter on iPhone.
  - Limrun (YC): simulators for agent companies, which its YC description says include Replit and Rork.

### (e) The weekend version, and what its launch post would say

**Option 1: "paste SwiftUI, see it, share a link."** A page built from SwiftUIWeb (Apache-2.0) with a small compile server. But MiniSwift already shipped exactly this and got 2 HN points twice.

**Option 2 (differentiated): `swiftui-snap`,** a CLI or GitHub Action that renders SwiftUI views to PNG on Linux, so Claude Code on the web, Codex cloud or Devin can *see* the UI they just wrote. **Launch post:** "Your cloud agent can't run a simulator. Now it can still look at its SwiftUI."

### (f) Verdict: adoption evidence **weak**

**Biggest reason:** a free version already exists (MiniSwift, and Tokamak before it), and every launch drew 6 HN points or fewer. The people who care most about SwiftUI already own a Mac with Xcode 27 previews, and AI builders get previews from funded platforms.

---

## Idea 3 (id 24): a user-pays AI wallet as a native Swift / Foundation Models provider

### (a) Closest free and open-source projects, and how much they are used

| Project | What it does | Adoption |
|---|---|---|
| [HeyPuter/puter](https://github.com/HeyPuter/puter) / Puter.js ([user-pays docs](https://docs.puter.com/user-pays-model/)) | User-pays AI for web apps. **No Swift SDK found** (`gh search repos "puter swift"` returned nothing relevant). | 43,600★, created 2024-03-03. `@heyputer/puter.js` had **53,437 npm downloads** from 2026-08-23 to 09-21 (script-tag use is not counted). Best HN result: [21 points](https://news.ycombinator.com/item?id=40471199) (2024) |
| [pollinations/pollinations](https://github.com/pollinations/pollinations) BYOP ("Bring Your Own Pollen") | OAuth 2.1 PKCE, per-app caps, model allowlists, expiry | 5,127★ |
| [Merit-Systems/echo](https://github.com/Merit-Systems/echo) ("The User Pays AI SDK") | Shared-wallet SDKs | 546★, created 2025-05-05, last push 2026-06-26. npm over the same window: echo-react-sdk 672 + echo-typescript-sdk 844. HN: [2 points](https://news.ycombinator.com/item?id=47822152) |
| [OpenRouter OAuth PKCE](https://openrouter.ai/docs/use-cases/oauth-pkce) | A user-controlled API key for the app. The docs give no Swift or mobile guidance and do not mention app-set caps. | `@openrouter/ai-sdk-provider` had 9,902,653 npm downloads/month, mostly developer-paid use |
| Swift / Foundation Models side | [huggingface/AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel); [anthropics/ClaudeForFoundationModels](https://github.com/anthropics/ClaudeForFoundationModels) (auth is an App Attest client ID from the Anthropic console, so the **developer** pays); [AIProxySwift](https://github.com/AIProxyTeam/AIProxySwift); [MacPaw/OpenAI](https://github.com/MacPaw/OpenAI) | 942★; 305★ (301 on 09-22); 447★; 2,946★ |
| Swift user-pays or OpenRouter OAuth SDKs | `gh search "openrouter swift"` found 2 repos with 0★. `"foundation models provider"` found [MLXFoundationModel](https://github.com/matiasvillaverde/MLXFoundationModel) with 1★. | Nothing with traction |
| HN demand | ["Sign in with your ChatGPT account for free AI"](https://news.ycombinator.com/item?id=48922687); "RNet: users pay for their own AI usage" | 3 points each |

### (b) Communities that would spread it

- **Reddit** (reddapi.dev): r/iOSProgramming 204,491; r/swift 142,070; r/vibecoding 349,412.
- **Other channels:** indie Apple developers (Swift Forums, iOS Dev Weekly and similar).
- **How it would spread:** the market is two-sided. Every developer's end users must also have, or create, a funded AI account. That slows word of mouth compared with a single-sided developer tool.

### (c) Cost to serve free users

**Pure client SDK** (OAuth PKCE to OpenRouter or Pollinations through `ASWebAuthenticationSession`, key stored in Keychain): **≈ $0/month** at 10k or 100k users, apart from a docs site.

**Thin broker for token exchange and a caps ledger on Cloudflare Workers.** Assumption: 300 AI calls per user per month pass through the broker. Prices are from [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/): $5/month includes 10M requests, then $0.30 per million; D1 and KV stay within their included amounts.

| Free users | Requests/month | Cost |
|---|---|---|
| 10k | 3M | **$5/month** |
| 100k | 30M | **≈ $11/month** |

**Running the wallet itself** (holding money, payments, fraud and chargebacks): the cost becomes compliance rather than compute. Amount unknown.

### (d) Has Apple or anyone else shipped or announced it?

- **Apple already covers most of it for native apps:**
  - Foundation Models on Private Cloud Compute is **free, with "no token costs"**, for developers with fewer than 2M first-time downloads.
  - Each user gets a **daily limit counted against their iCloud account, upgradable through iCloud+**. In effect this is Apple's own user-pays model ([summary of WWDC26](https://blakecrosley.com/blog/foundation-models-private-cloud-compute)).
  - The provider session ([WWDC26 #339](https://developer.apple.com/videos/play/wwdc2026/339/)) recommends token-provider sign-in flows and App Attest. It has no system-level model picker for end users.
- **The subscription accounts users actually pay for are closed:**
  - Anthropic began rejecting subscription OAuth tokens in third-party tools on 2026-01-09 and put the ban in its docs on 2026-02-19 ([WinBuzzer](https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/)).
  - OpenAI's "Sign in with ChatGPT" shipped only inside Codex tooling as of April 2026 ([explainx, secondary](https://explainx.ai/blog/login-with-chatgpt-codex-subscription-oauth-2026)).
- **Funded or large players on the web side:** Puter, Merit Systems (Echo), and OpenRouter (reported as acquired by Stripe in earlier notes).

### (e) The weekend version, and what its launch post would say

**`FundedModel`**, a Swift package that conforms to `LanguageModel`:
- It cascades from the on-device model, to PCC (free), to the user's own OpenRouter account connected through PKCE.
- It includes a SwiftUI "Connect your AI" button and cap settings.

**Launch post:** "Ship AI in your iOS app with a $0 inference bill. Apple's model first, then your user's own OpenRouter key. One drop-in `LanguageModel`."

### (f) Verdict: adoption evidence **weak**

**Biggest reason:** Apple's free PCC tier, with per-user quotas funded by iCloud+, already gives small native apps AI with no inference bill. What remains is frontier models paid for by the user. That has shown little pull even on the web (Echo sits around 1.5k npm downloads/month after about 16 months), and the providers users actually subscribe to, Claude and ChatGPT, forbid subscription OAuth or have not opened it.

---

## Ranking by adoption potential

1. **Idea 1 (medium).** It is the only one with proven demand next to it (1k–5k★ projects) and a free local cost profile. Build it only on the public signed-shortcut route, and assume Apple may ship native MCP for App Intents.
2. **Idea 3 (weak).** It is cheap to serve, but Apple's PCC tier absorbs most of it.
3. **Idea 2 (weak).** A free version already exists and has drawn little attention.
