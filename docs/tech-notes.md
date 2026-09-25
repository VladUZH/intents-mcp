# Technical ground truth for intents-mcp

Research date: **2026-09-25**. Machine: macOS 27.0 (build 26A428), Darwin 27.0.0, arm64, Xcode 26.6 (17F113; no macOS 27 SDK installed), Apple Swift 6.3.3.

**How things were checked.** Local checks were read-only: `find`, `jq`, a Python counting script, `plutil`, `codesign -d`, `shortcuts help`, `man shortcuts`, and `rg` over the OS shared cache. **No shortcut was created, signed, imported or run.** Web sources are cited inline and were all read on 2026-09-25.

**Provenance tags:**
- **[local]**: observed on this Mac.
- **[src]**: read in source code.
- **[doc]**: stated in a README, blog or doc and not re-verified.
- **(inference)**: my reasoning, not something observed or stated.

---

## 0. The findings that change the build

1. **The metadata is easy to read and needs no permission.**
   - Every App Intent ships as JSON in `…/Metadata.appintents/extract.actionsdata`.
   - This Mac has **223 such files and 1,269 actions (1,225 unique)**. **942 are discoverable** in Shortcuts, and **489 of those are outside System Settings panes**.
   - Third-party apps contribute only **23 actions from 8 of 50 apps**. Only one of those returns output.
2. **Most useful actions take entity parameters, which cannot be passed as text.**
   - 666 of 942 discoverable actions take an entity or array (a note, a reminder, a message).
   - Engine round-trips reported by shortcutkit show an entity parameter **rejects a plain string** and accepts only a variable, for example the output of a Find action.
   - So v1 needs "find" tools (entity queries) chained to "act" tools, or a scope limited to primitive-only actions. Only 129 unique discoverable, background-capable actions have primitive or enum parameters exclusively.
3. **The public route is confirmed and has been used in the wild.**
   - Steps: generate the plist, run `shortcuts sign`, the user clicks "Add Shortcut", then `shortcuts run <UUID> --input-path … --output-path …`.
   - sweetrb/apple-notes-mcp (133★) ships exactly this for Notes App Intents on macOS 26/27.
   - The `shortcuts` binary itself carries the private `com.apple.shortcuts.background-running` entitlement that Action Relay needs SIP turned off to get.
4. **Signing is not purely local and needs an Apple Account, but not the $99 program.**
   - Apple's guide: "When you sign a shortcut, Apple receives a copy for validation."
   - The man page says `people-who-know-me` "will sign locally", while `anyone` "will notarize via iCloud".
   - shortcutkit reports signing fails unless the Mac is signed into iCloud.
   - This conflicts with any "nothing leaves your Mac" wording. See §3.4.
5. **First-run consent prompts stall background runs.**
   - Each wrapper must be run once in the foreground and set to "Always Allow", after install **and after every upgrade** (sweetrb README).
   - That is a second manual step per tool, on top of the "Add Shortcut" click.
6. **The Swift MCP SDK 0.12.1 breaks with current Codex.**
   - Object-valued `experimental` capabilities fail `initialize` ([swift-sdk#287](https://github.com/modelcontextprotocol/swift-sdk/issues/287), open since 2026-09-14; fix PRs #276 and #289 open).
   - The SDK also lags the current MCP spec: it supports up to 2025-11-25, and the latest is **2026-07-28**.
7. **Apple has shipped no public route from MCP to App Intents as of macOS 27.**
   - MCP ships only in developer tools: `xcrun mcpbridge`, `safaridriver --mcp` and lldb-mcp.
   - macOS 27 contains a private MCP *client* (`GenerativeAgents.framework`), which is a Sherlock risk to watch.
8. **Homebrew needs neither notarization nor the $99 program** for a source-built formula.
   - homebrew-core is not open to a repo under 30 days old, and self-submission needs 225★.
   - Tap installs *are* counted in public analytics.

---

## 1. App Intents metadata

### 1.1 Where it lives [local]

- **Path in an app:** `<App>.app/Contents/Resources/Metadata.appintents/extract.actionsdata`, next to `version.json` (Notes: `{"toolsVersion": "27A200c", "version": "3.0"}`).
- **Path in a framework:** `<Name>.framework/Versions/A/Resources/Metadata.appintents/…`.
- App extensions (`.appex`, for example widgets) carry their own copy.
- One legacy location exists: `Weather.app/Contents/Resources/Link.data/extract.actionsdata` (generator `link`).
- **Format:** single-line UTF-8 JSON. It is generated at build time by Xcode: `generator = {"name": "xcode-tools", "version": "<Xcode build>"}`. 205 of 223 files say `27A200c`; third-party apps show `17E202`, `17C529` and so on.
- **Permissions:** reading these files needs **no TCC permission**. The Shortcuts app's own action index (`~/Library/Shortcuts/ToolKit/Tools-prod.*.sqlite`, documented by [shortcutkit](https://github.com/frontboat/shortcutkit/blob/main/docs/extraction.md) [doc]) is TCC-protected: `ls ~/Library/Shortcuts` returned "Operation not permitted" [local].

Scan command:

```
find /Applications /System/Applications /System/Library /System/Cryptexes/App \
     /System/iOSSupport /Library/Apple ~/Applications -xdev -name extract.actionsdata
```

### 1.2 JSON structure (field names only) [local]

**Top level:** `actions`, `entities`, `enums`, `queries`, `autoShortcuts`, `generator`, `version`, `shortcutTileColor`, `assistantIntents`, `assistantEntities`, `negativePhrases`, `assistantIntentNegativePhrases`, and sometimes `autoShortcutProviderMangledName`.

**`actions`** is keyed by the action identifier. The dictionary key equals `identifier`, and it is the `AppIntentIdentifier` a shortcut uses. Counts below are out of 1,269 actions.

| Field | Present on | Meaning / values |
|---|---|---|
| `identifier`, `fullyQualifiedTypeName`, `mangledTypeName(V2)` | all | e.g. `AppendToNoteLinkAction`, `Notes.AppendToNoteIntent` |
| `title` | 1,195 | `{key, alternatives[], table?, defaultValue?}`. `key` is the English text **or a localization key** |
| `descriptionMetadata` | 871 | `descriptionText.key`, `searchKeywords`, `categoryName` |
| `parameters[]` | all | see below |
| `outputType` | 562 | Same encoding as a parameter `valueType`. Absent means no output |
| `isDiscoverable` | 1,257 | Apple: if true, "Siri, Spotlight, and the Shortcuts app can discover and use the app intent" (default true) ([doc](https://developer.apple.com/documentation/appintents/appintent/isdiscoverable)) |
| `openAppWhenRun` | 1,258 | Deprecated in 26.0: "Please provide 'supportedModes' instead" ([doc](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun)) |
| `supportedModes` | 1,253 | Integer bit field. On this Mac `1` always pairs with `openAppWhenRun:false` (850 actions) and `2` with `true` (395), so 1 = background and 2 = foreground (**inference**; Apple documents only `IntentModes` as Swift values, [doc](https://developer.apple.com/documentation/appintents/intentmodes)) |
| `systemProtocols[]` | all | e.g. `com.apple.link.systemProtocol.DeleteEntity` (32), `…CreateEntity` (17), `…OpenEntity` (217), `…PropertyUpdater` (281), `…AssistantIntent` (176), `…LongRunning` (5), `…Undoable` (4) |
| `sideEffect` | all | `null` or `{"changeEffect": -1, "effect": -1}` |
| `authenticationPolicy` | 1,258 | 0 for 1,213 actions; 1 or 2 for 45 (probably "requires unlock"; inference) |
| `actionConfiguration` | 387 | Parameter summary, e.g. `"${operation} ${text} to ${entity}"` |
| `attributionBundleIdentifier` | 296 | For framework and extension actions: the app they appear under (`com.apple.clock`, `com.apple.systempreferences`, …) |
| others | | `availabilityAnnotations`, `effectiveBundleIdentifiers`, `presentationStyle`, `requiredCapabilities`, `visibilityMetadata`, `assistantDefinedSchemas`, `typeSpecificMetadata`, `systemProtocolMetadata(V2)`, `deprecationMetadata`, `customIntentClassName` |

**Parameters** (2,218 in total) have:
- `name`: **the key used in the shortcut plist**
- `title`, `parameterDescription` (638 of them), `isOptional`, `isInput`
- `valueType`, `resolvableInputTypes`
- `typeSpecificMetadata`: defaults, number bounds, multiline flag
- `dynamicOptionsSupport`, `capabilities`, `inputConnectionBehavior`, and sometimes `queryIdentifier`

**`valueType`** is a one-key object:

| Kind | Count |
|---|---|
| `entity` | 810 |
| `primitive` | 663 |
| `linkEnumeration` | 342 |
| `array` | 284 |
| `intents` | 49 |
| `alternative` | 44 |
| `searchCriteria` | 17 |
| `foundation` | 6 |
| `measurement` | 2 |
| `builtIn` | 1 |

`primitive.wrapper.typeIdentifier` is an integer. Mapped from the parameter titles on this Mac (**inference, undocumented**):

| Code | Type |
|---|---|
| 0 | String |
| 1 | Bool |
| 2 | Int |
| 7 | Double |
| 8 | Date |
| 9 | DateComponents |
| 10 | Location |
| 11 | URL |
| 12 | AttributedString |

**Other top-level sections:**
- **`entities`** (988): `typeName`, `displayTypeName`, `defaultQueryIdentifier`, `properties[]` (`identifier`, `title`, `valueType`, `isOptional`, `spotlightAttributeKey`).
- **`queries`** (599): `entityType`, `parameters[]` (filterable properties with `comparators`), `sortingOptions`, `capabilities`.
- **`enums`** (530): `identifier`, `cases[]` (`identifier`, `displayRepresentation.title.key`).
- **`autoShortcuts`**: `actionIdentifier`, `phraseTemplates`, `shortTitle`, `systemImageName`.

**Worked example.** Notes `AppendToNoteLinkAction` has these parameters and returns a `NoteEntity`, with `openAppWhenRun:false`:
- `operation`: enum `AppendOperation` = `append|prepend`, default `append`
- `entity`: `NoteEntity`, required
- `text`: type 12
- `section`, `ignoreWhitespace`, `interpretAsMarkdown`

**Localization.** When `title.key` is a key rather than text, the English string is in a compiled `.loctable`, a binary plist keyed by locale, in the bundle's Resources. For example, Voice Memos' `Localizable.loctable` maps `CREATE_RECORDING_INTENT_NAME_PARAMETER` to "Name" [local]. Tool names must be resolved this way.

### 1.3 Apple's apps and frameworks use the same format, but spread out [local]

| Location | Files | Actions | Discoverable | Largest |
|---|---|---|---|---|
| `/Applications` (third-party) | 10 | 23 | 19 | Microsoft Teams 8, WhatsApp 5; Word, Excel, PowerPoint and Outlook 2 each; CotEditor 1; MacWhisper 1 |
| `/System/Applications` | 48 | 300 | 196 | Notes 52, Books 28, Freeform 24, Mail 23, Shortcuts 21, Voice Memos 19, Podcasts 18, Weather 17, Journal 17, Preview 17 |
| `/System/Library/CoreServices` | 10 | 39 | 36 | Finder 16, WindowManager 7, Control Center 6 |
| `/System/Library/PrivateFrameworks` | 52 | 312 | 182 | PhotosUICore 43, **RemindersAppIntents 39**, PhotosUIPrivate 29, **CalendarLink 20** |
| `/System/Library/ExtensionKit` (Settings panes, widgets) | 74 | 465 | 453 | AccessibilitySettingsWidgetExtension 167, DesktopSettingsIntents 33 |
| `/System/iOSSupport` (Catalyst copies) | 15 | 127 | 78 | PassKitUI 24, ChatKit 23 |
| `/System/Library/Frameworks` (public) | 12 | 3 | 0 | entities only |
| **Total** | **223** | **1,269** | | 1,225 unique by `fullyQualifiedTypeName` |

- **Many Apple apps keep their intents in frameworks.**
  - 26 of 65 apps in `/System/Applications` have any metadata inside their bundle.
  - Reminders has 2 actions in the app and 39 in `RemindersAppIntents.framework`. Calendar is entirely in `CalendarLink.framework`.
  - The indexer must scan `/System/Library` and map each action to its app. `attributionBundleIdentifier` covers only some of them.
  - shortcutkit reports that Reminders' framework intents are written as `com.apple.reminders.…` [doc].
- **Safari's intents are not on disk as `extract.actionsdata`** (it lives in the App cryptex). Yet Apple's own `Notify Me When.wflow` calls `com.apple.mobilesafari.RequestWebPageContextIntent` [local]. The file scan is therefore a lower bound.
- **Built-in Shortcuts actions are not App Intents.** Examples: `is.workflow.actions.filter.calendarevents`, `…getvalueforkey`, `…output`. A generated wrapper can use them, but the scan does not list them. Dominic-DK harvested 497 of them from `WFActionRegistry` [src].

### 1.4 How many are good agent tools? [local]

Counted on unique actions:

| Scope | Unique | Discoverable | Discoverable and background (`openAppWhenRun:false`) | …and returns output | Background with only primitive or enum parameters |
|---|---|---|---|---|---|
| All | 1,225 | **942** | 638 | 437 | 129 |
| Excluding ExtensionKit (Settings panes, widgets) | 760 | **489** | 308 | 136 | 84 |
| Apple apps + CoreServices | 339 | 232 | 149 | 78 | 42 |
| Third-party | 23 | 19 | 7 | **1** | 5 |

- **The "about 600" claim** from the one-pager (Apple apps plus private frameworks) is in range, but depends on the definition. Measured alternatives: **"~940 actions Shortcuts can discover"**, or **"~490 outside System Settings"**. Ship the counting script so readers can reproduce the number.
- **Entity parameters:**
  - 633 of the 637 entity parameters on discoverable actions list no `resolvableInputTypes`.
  - 554 declare `dynamicOptionsSupport`.
- **Third-party apps are thin on this Mac.**
  - 16 of 23 actions open the app.
  - Office apps expose only create and open.
  - Only MacWhisper's `TranscribeAudioIntent` returns output.
- **Destructive actions should be off by default:**
  - 27 unique discoverable actions declare `DeleteEntity`: `DeleteNotesLinkAction`, `DeleteRemindersAppIntent`, `DeleteEventIntent`, `DeleteMessageIntent`, and others.
  - Finder's `TrashItemsIntent` should be treated the same way.
  - Set MCP `destructiveHint` on all of these.

**Samples.** `->out` means the action returns output; `[opens app]` means it runs in the foreground.
- **Notes (47):** `CreateNoteLinkAction->out(name, contents, folder, interpretAsMarkdown)`, `AppendToNoteLinkAction->out`, `CreateFolderLinkAction->out(name)`, `CreateTableLinkAction->out(name, csvString, note)`, `AddTagsToNotesLinkAction->out`, `PinNotesLinkAction->out`, `OpenNoteLinkAction [opens app]`
- **Mail (14):** `SendMail(to, cc, bcc, subject, body, account, attachments, inReplyTo)`, `ArchiveMessageIntent->out`, `SetMailMessageIsRead`, `ComposeMessageIntent [opens app]`
- **Reminders (31):** `TTRCreateReminderAppIntent->out(title, note, dueDate, list, …)`, `CompleteReminderAppIntent->out`, `UpdateReminderAppIntent->out`, `TTRSearchRemindersAppIntent [opens app]`
- **Calendar (16):** `CreateEventIntent->out(title, startDate, endDate, …)`, `EditEventIntent->out`, `RespondToInboxItemIntent`, `DeleteEventIntent`
- **Finder (16):** `GetSelectedItemsIntent->out`, `GetLocationIntent->out`, `TrashItemsIntent->out`; most others `[opens app]`

---

## 2. The `shortcuts` command-line tool

### 2.1 Subcommands (from `shortcuts help` on macOS 27.0) [local]

```
shortcuts run <shortcut-name-or-identifier> [--input-path <input-path> ...] [--output-path <output-path>] [--output-type <output-type>]
shortcuts list [--folder-name <folder-name>] [--folders] [--show-identifiers]
shortcuts view <shortcut-name>
shortcuts sign [--mode <mode>] --input <input> --output <output>
      -m, --mode   The signing mode (anyone, people-who-know-me). (default: people-who-know-me)
      "It also supports signing a shortcut in the old format."
```

Short forms: `-i`, `-o`, `-f`, `-m`. There is no `--version`, and there is **no import subcommand**.

### 2.2 Input, output and limits

- **Man page** (`/usr/share/man/man1/shortcuts.1`, dated 2021-09-08) [local]:
  - `--input-path`: "Can be dropped, or set to "-" for stdin."
  - `--output-path`: "Can be omitted, or set to "-" for stdout."
  - `--output-type`: a UTI. "If not provided shortcuts will attempt to infer the output type from the output filename, or use the default type of the output content."
- **Apple guide** ([Run shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)):
  - `-i` takes file paths, including wildcards. "When you pass a file path using a pipe (|), the path is treated as text."
  - `-o` writes a file and picks the format from the file extension.
  - "The shortcuts command will exit 0 on a successful run or 1 on error."
  - "When a shortcut asks for input, the command line process pauses, awaiting user input."
- **Implications (inference plus third-party reports):**
  - **Input must be a path or stdin, not literal JSON text.** recursechat and bradwindy pass text to `-i`, which is a bug. [src]
  - **stdin blocks.** With `-i -` the CLI reads stdin before it resolves the shortcut, and hangs if stdin stays open ([cyanheads/macos-mcp-server#17](https://github.com/cyanheads/macos-mcp-server/issues/17), 2026-09-24).
    - **Never let the child inherit the MCP server's stdin**, which is the JSON-RPC pipe. Write a temporary JSON file, or give the child its own closed pipe.
  - **Missing shortcut:** the error is `Error: The operation couldn’t be completed. Couldn’t find shortcut`, exit code 1 (same issue).
  - **Identity:** run by UUID from `shortcuts list --show-identifiers`, not by name. The imported name comes from the file name, and non-ASCII names can come back NFD-normalized (Dominic-DK [src]).
  - **Asleep Mac:** runs work with the screen locked (62/63 measured by Dominic-DK [doc]) but not while the Mac is asleep.
  - **Timeouts:** Claude Desktop has a request timeout of about 60 s, so long intents need an async pattern ([RunShortcutsMCP](https://github.com/pricemi115/RunShortcutsMCP) README [doc]).
- **Entitlements** (`codesign -d --entitlements :- /usr/bin/shortcuts`) [local]: `com.apple.shortcuts.background-running`, iCloud and CloudKit container `iCloud.is.workflow.my.workflows`, `com.apple.security.network.client`, `keychain-access-groups = com.apple.sharing.appleidauthentication`, and mach-lookup to `com.apple.siri.VoiceShortcuts.xpc` and `com.apple.siriactionsd.xpc`.
  - `shortcuts run` is therefore Apple's entitled, public path into the same background runner that Action Relay reaches over private XPC.

### 2.3 Consent prompts and settings

- **Prompt strings in macOS 27 WorkflowKit** [local, cache strings]: `Allow “%@” to run actions from “%@”?`, `Allow “%1$@” to output %2$@?`, `Allow “%1$@” to share %2$@ with %3$@?`, `Always Allow`.
- **A first-run prompt cannot appear in a background CLI run, so the run stalls.** sweetrb/apple-notes-mcp's shortcuts README: "After install and after every upgrade, run each bridge once in the foreground in Shortcuts.app and choose **Always Allow**" [src].
- **Advanced settings** (Shortcuts app, macOS 27) [local, loctable]: "Allow Running Scripts", "Allow Sharing Large Amounts of Data", "Allow Deleting Without Confirmation", "Allow Deleting Large Amounts of Data", "Private Sharing". Apple's pages: [privacy settings](https://support.apple.com/guide/shortcuts-mac/adjust-privacy-settings-apd961a4fc65/mac) and [advanced settings](https://support.apple.com/guide/shortcuts-mac/advanced-shortcuts-settings-apdfeb05586f/mac).

---

## 3. The .shortcut file format for an App Intent action

### 3.1 First-party ground truth: Apple's own unsigned workflows on this Mac [local]

macOS ships binary-plist workflows. Decode them with `plutil -convert json -o - <file>`:
- `/System/Library/PrivateFrameworks/WorkflowKit.framework/Versions/A/Resources/Gallery.bundle/Contents/Resources/*.wflow` (7 gallery shortcuts)
- `/System/Library/PrivateFrameworks/VoiceShortcuts.framework/Versions/A/Resources/Notify Me When.wflow`

They confirm the following.
- **Action identifier = `<CFBundleIdentifier>.<actions key>`.**
  - `SummarizePDF.wflow` calls `com.apple.WritingTools.WritingToolsAppIntentsExtension.SummarizeTextIntent`.
  - That extension's `CFBundleIdentifier` is `com.apple.WritingTools.WritingToolsAppIntentsExtension`.
  - Its `extract.actionsdata` defines `SummarizeTextIntent` with the parameters `text` and `summaryType` (enum `SummaryIntentMode`: `summarize`, `createKeyPoints`).
- **Parameter key = `parameters[].name`. Enum value = case `identifier` as a plain string:** `"summaryType": "createKeyPoints"`.
- **`AppIntentDescriptor`** sits inside `WFWorkflowActionParameters`:
  - `{"TeamIdentifier": "0000000000", "BundleIdentifier": "com.apple.mobilesafari", "Name": "Safari", "AppIntentIdentifier": "RequestWebPageContextIntent"}`
  - Sometimes with `"ActionRequiresAppInstallation": true`.
- **Bundle IDs can be the iOS ones.** `ActionItems.wflow` uses `com.apple.mobilenotes` for Notes; the Mac bundle is `com.apple.Notes`. sweetrb's working Mac bridge uses `com.apple.Notes` [src].
- **Entity query as a Find action:** `is.workflow.actions.filter.notes` with `AppIntentDescriptor.AppIntentIdentifier = "NoteEntity"` and a `WFContentItemFilter` (`WFContentPredicateTableTemplate`, `Property: "Name"`, `Operator: 99`).
- **Shortcut Input:** `{"Value": {"Type": "ExtensionInput"}, "WFSerializationType": "WFTextTokenAttachment"}`, with `WFWorkflowHasShortcutInputVariables: true`.

### 3.2 Annotated skeleton: JSON in, one third-party App Intent with 2 parameters, JSON out

Sources for the key names:
- [local] Apple `.wflow` files above
- [shortcutkit](https://github.com/frontboat/shortcutkit/blob/main/docs/shortcut-file-format.md) (engine round-trips on macOS 27) [src/doc]
- [sweetrb bridge builders](https://github.com/sweetrb/apple-notes-mcp/blob/main/scripts/build-native-tags-shortcut.py) [src]
- [Dominic-DK recipes](https://github.com/Dominic-DK/mac-shortcuts-mcp/blob/main/recipes/contacts-find.plist) [src]
- [action-relay WorkflowBuilder.swift](https://github.com/tarqd/action-relay/blob/main/Sources/action-relay/WorkflowBuilder.swift) [src]
- a real Toolbox Pro export ([extratone/i](https://github.com/extratone/i/blob/main/shortcuts/source/createpost.html)) with `TeamIdentifier "NWHDL7X5B3"`

```xml
<plist version="1.0"><dict>
  <!-- No WFWorkflowName: the imported name comes from the FILE NAME (the signer drops WFWorkflowName) -->
  <key>WFWorkflowClientVersion</key><string>5037.0.17</string>   <!-- any; Apple files show 5022.0.12 / 4018.0.4 -->
  <key>WFWorkflowMinimumClientVersion</key><integer>900</integer>
  <key>WFWorkflowMinimumClientVersionString</key><string>900</string>
  <key>WFWorkflowIcon</key><dict>
    <key>WFWorkflowIconStartColor</key><integer>463140863</integer>
    <key>WFWorkflowIconGlyphNumber</key><integer>61440</integer></dict>
  <key>WFWorkflowImportQuestions</key><array/>
  <key>WFWorkflowTypes</key><array/>
  <key>WFQuickActionSurfaces</key><array/>
  <key>WFWorkflowInputContentItemClasses</key><array>
    <string>WFStringContentItem</string><string>WFDictionaryContentItem</string><string>WFGenericFileContentItem</string></array>
  <key>WFWorkflowOutputContentItemClasses</key><array><string>WFStringContentItem</string></array>
  <key>WFWorkflowHasShortcutInputVariables</key><true/>
  <key>WFWorkflowHasOutputFallback</key><false/>
  <key>WFWorkflowActions</key><array>

    <!-- 1 Get Dictionary from Input -->
    <dict><key>WFWorkflowActionIdentifier</key><string>is.workflow.actions.detect.dictionary</string>
      <key>WFWorkflowActionParameters</key><dict>
        <key>UUID</key><string>…0001</string>
        <key>WFInput</key><dict><key>Value</key><dict><key>Type</key><string>ExtensionInput</string></dict>
          <key>WFSerializationType</key><string>WFTextTokenAttachment</string></dict></dict></dict>

    <!-- 2,3 Get Dictionary Value for "title" / "count" (sweetrb adds is.workflow.actions.gettext after each:
             "Dictionary Value is an untyped Content Item") -->
    <dict><key>WFWorkflowActionIdentifier</key><string>is.workflow.actions.getvalueforkey</string>
      <key>WFWorkflowActionParameters</key><dict>
        <key>UUID</key><string>…0002</string>
        <key>WFGetDictionaryValueType</key><string>Value</string>
        <key>WFDictionaryKey</key><string>title</string>
        <key>WFInput</key><dict><key>Value</key><dict><key>Type</key><string>ActionOutput</string>
          <key>OutputUUID</key><string>…0001</string><key>OutputName</key><string>Dictionary</string></dict>
          <key>WFSerializationType</key><string>WFTextTokenAttachment</string></dict></dict></dict>

    <!-- 4 THE APP INTENT: identifier = "<bundleID>.<intent id>" -->
    <dict><key>WFWorkflowActionIdentifier</key><string>BUNDLE_ID.INTENT_ID</string>
      <key>WFWorkflowActionParameters</key><dict>
        <key>AppIntentDescriptor</key><dict>
          <key>TeamIdentifier</key><string>TEAM_ID</string>       <!-- 0000000000 for Apple; from `codesign -dv` -->
          <key>BundleIdentifier</key><string>BUNDLE_ID</string>
          <key>Name</key><string>APP_NAME</string>
          <key>AppIntentIdentifier</key><string>INTENT_ID</string>
          <key>ActionRequiresAppInstallation</key><true/></dict>  <!-- optional -->
        <key>UUID</key><string>…0004</string>
        <key>CustomOutputName</key><string>Result</string>         <!-- optional -->
        <!-- String parameter: MUST be a token string (a bare attachment is rejected) -->
        <key>PARAM_1_NAME</key><dict><key>Value</key><dict>
            <key>string</key><string>&#xFFFC;</string>
            <key>attachmentsByRange</key><dict><key>{0, 1}</key><dict>
              <key>Type</key><string>ActionOutput</string><key>OutputUUID</key><string>…0002</string>
              <key>OutputName</key><string>Dictionary Value</string></dict></dict></dict>
          <key>WFSerializationType</key><string>WFTextTokenString</string></dict>
        <!-- Number, enum or ENTITY parameter: bare attachment (a token string is rejected for numbers; a plain string is rejected for entities) -->
        <key>PARAM_2_NAME</key><dict><key>Value</key><dict>
            <key>Type</key><string>ActionOutput</string><key>OutputUUID</key><string>…0003</string>
            <key>OutputName</key><string>Dictionary Value</string></dict>
          <key>WFSerializationType</key><string>WFTextTokenAttachment</string></dict>
      </dict></dict>

    <!-- 5 Stop and Output -->
    <dict><key>WFWorkflowActionIdentifier</key><string>is.workflow.actions.output</string>
      <key>WFWorkflowActionParameters</key><dict><key>UUID</key><string>…0005</string>
        <key>WFOutput</key><dict><key>Value</key><dict><key>string</key><string>&#xFFFC;</string>
          <key>attachmentsByRange</key><dict><key>{0, 1}</key><dict><key>Type</key><string>ActionOutput</string>
            <key>OutputUUID</key><string>…0004</string><key>OutputName</key><string>Result</string></dict></dict></dict>
          <key>WFSerializationType</key><string>WFTextTokenString</string></dict></dict></dict>
  </array>
</dict></plist>
```

**A more compact input form** (used by Dominic-DK [src]): skip actions 1–3 and attach `{"Type": "ExtensionInput", "Aggrandizements": [{"Type": "WFCoercionVariableAggrandizement", "CoercionItemClass": "WFDictionaryContentItem"}, {"Type": "WFDictionaryValueVariableAggrandizement", "DictionaryKey": "query"}]}` directly to the parameter.

**Caution.** Another project (leeguooooo/iphone-use#58) reports that `detect.dictionary` + `getvalueforkey` "silently yields empty values" in their setup; sweetrb reports the pattern working [src]. Test both forms.

### 3.3 Value encodings per parameter type

Source: shortcutkit engine round-trips on macOS 27, `data/encoding-roundtrips.json` [src].

| Parameter type | Engine state | Literal value | Bare `WFTextTokenAttachment` | `WFTextTokenString` |
|---|---|---|---|---|
| String | `WFVariableStringParameterState` | accepted | **rejected** | accepted |
| Int / Double | `WFNumberStringSubstitutableState` | accepted | accepted | **rejected** |
| Enum | `WFLinkEnumerationSubstitutableState` | case-id string | accepted | not listed |
| Entity | `WFLinkDynamicOptionSubstitutableState` | **plain string rejected** | accepted | **rejected** |

- **Entity literals written by the editor** are dictionaries such as `{"identifier": "notes:folder/…", "displayString": "…", "title": {"key": "…"}}` [src, extratone export]. Whether a hand-built one resolves is **unverified**.
- **The keys `serializedEntity` and `WFAppIntentEntity` were not found** in any source or OS string table.
- **Wrong parameter keys are silently ignored,** at least for built-in actions. Dominic-DK measured `Count` with key `WFInput` instead of `Input` returning 0, not 3 [src]. For App Intents the effect of a wrong key is **unknown**.

### 3.4 Signing

- **Modes.**
  - Man page: `people-who-know-me` (the default) "will sign locally, but only your devices, or people who have your contact info in their contacts, will be able to import the shortcut".
  - Man page: `anyone` "will notarize via iCloud" [local].
  - Apple guide: "When you sign a shortcut, Apple receives a copy for validation (to prevent unauthorized tampering when you share it)". People who know me: "Your contact info will be included in the shortcut file."
- **Account requirement.** shortcutkit says signing "requires the Mac to be signed into iCloud, even in `anyone` mode". The error string "In order to do this, you must be signed into iCloud." exists in macOS 27 WorkflowKit [doc + local].
  - **No source says a paid developer account is needed.** Signing is an end-user Apple Account feature.
  - Whether `people-who-know-me` makes any network call, or works offline, is **unverified**.
- **Container.** The signed file is AEA (`AEA1` magic).
  - Profile `hkdf_sha256_hmac__none__ecdsa_p256`: signed, **not encrypted**.
  - It wraps `Shortcut.wflow`, a binary plist.
  - An `anyone` file carries `SigningCertificateChain`: an Apple leaf certificate, then "Apple System Integration CA 4", then "Apple Root CA - G3". The leaf observed was valid for about 1 year.
  - Contact-signed files carry `AppleIDCertificateChain`, `AppleIDValidationRecord`, `SigningPublicKey` and `SigningPublicKeySignature` ([libshortcutsign](https://github.com/0xilis/libshortcutsign) [src]).
  - What the signer changes (diff of sweetrb's unsigned and signed pair): it removes `WFWorkflowName`, adds `WFQuickActionSurfaces` and `WFWorkflowHasOutputFallback`, and rewrites `WFWorkflowClientVersion`. **Actions are byte-identical.**
- **Signer quirks:**
  - It needs a `.shortcut` file name (a `.plist` fails with "isn't in the correct format": [TimeTracker#2](https://github.com/furuochen-dev/TimeTracker/issues/2)).
  - It sometimes rejects XML, and converting to a binary plist helps ([shortcuts-playground#6](https://github.com/viticci/shortcuts-playground-plugin/issues/6)).
  - It fails confusingly under a sandboxed host ([#10](https://github.com/viticci/shortcuts-playground-plugin/issues/10)).
  - Its exit status is unreliable, so check for the `AEA1` magic ([cherri#49](https://github.com/electrikmilk/cherri/issues/49)).
- **Recommendation for intents-mcp (inference).**
  - Default to `people-who-know-me`: it is the CLI default, described as local, and the wrapper is only imported on the same Mac.
  - Test whether it imports without "Private Sharing" enabled.
  - Tell users plainly that signing needs an iCloud login and may contact Apple.
  - Avoid third-party signing services such as HubSign (network; reported returning 403 in 2026-07) and offline signers (these need keys extracted from a jailbroken device).

### 3.5 Open-source generators and how they sign

| Project | ★ / license / language | App Intents support | Signing |
|---|---|---|---|
| [electrikmilk/cherri](https://github.com/electrikmilk/cherri) | 1,620 / GPL-2.0 / Go | `appIntent{…}` builder adds a descriptor with team `0000000000` (Apple apps only). Custom `action 'com.x.Y' …` definitions do not add a descriptor. | `shortcuts sign … -m people-who-know-me` (or `anyone`), with a HubSign fallback (`signing.go`) |
| [viticci/shortcuts-playground-plugin](https://github.com/viticci/shortcuts-playground-plugin) | 1,126 / MIT / Python | Agent skill, not MCP. First-party catalogs (ToolKit v78 on macOS 27: 2,731 IDs). Third-party intents are IDs only, without schemas; [issue #17](https://github.com/viticci/shortcuts-playground-plugin/issues/17) proposes `extract.actionsdata` plus codesign Team ID, the same idea as intents-mcp. | `bin/sign-shortcut`, default `anyone`, retries with a binary plist |
| [frontboat/shortcutkit](https://github.com/frontboat/shortcutkit) | 2 / MIT / TypeScript | 434 built-ins and 1,441 Apple App Intents derived from the engine; `tools/dump-appintents-actions.py` for third-party apps | `shortcuts sign --mode anyone` |
| [sweetrb/apple-notes-mcp](https://github.com/sweetrb/apple-notes-mcp) | 133 / MIT / TypeScript | Python plist builders calling Notes `…LinkAction` intents | `anyone`; signed files committed |
| [Dominic-DK/mac-shortcuts-mcp](https://github.com/Dominic-DK/mac-shortcuts-mcp) | 14 / MIT / TypeScript | Built-in actions only; 539-action catalog | `anyone` at install |
| Jellycuts ([Open-Jellycore](https://github.com/OpenJelly/Open-Jellycore)) | 121 / GPL-3.0 / Swift | Last push 2024-06; exports a plist | No signing found |
| shortcuts-js, ScPL | archived or stale | Predate App Intents | — |

---

## 4. Existing App Intents or Shortcuts to MCP projects

Stats from `gh api` on 2026-09-25.

| Project | ★ | Created / last push | Mechanism | Where it fails |
|---|---|---|---|---|
| [tarqd/action-relay](https://github.com/tarqd/action-relay) ([write-up](https://tarq.net/posts/action-relay-shortcut-actions-mcp/)) | 5 | 2026-03-02 / 2026-04-08 | Parses `extract.actionsdata`, builds a one-action workflow plist in memory, sends it over private XPC to `com.apple.WorkflowKit.BackgroundShortcutRunner` (`runWorkflowWithDescriptor:…`). Entity queries become `find_*` tools. | Needs **SIP and AMFI disabled** plus a self-signed private entitlement. Entity parameters are raw ID strings. Stale; research tool |
| [bradwindy/app-intents-mcp](https://github.com/bradwindy/app-intents-mcp) | 1 | 2025-12-16 / 2026-07-08 | Discovers intents, then fuzzy-matches a **user-made** shortcut and runs `shortcuts run <name> -i <JSON string>` | README: "WORK IN PROGRESS: Not yet working". `-i` misuse. Falls back to instructions for building the shortcut by hand |
| [Dominic-DK/mac-shortcuts-mcp](https://github.com/Dominic-DK/mac-shortcuts-mcp) | 14 | 2026-09-19 / 2026-09-21 | 9 bundled XML recipes → `shortcuts sign --mode anyone` → `open -g` → user clicks Add (`--auto` clicks it through Accessibility) → `shortcuts run <UUID> -i in.txt -o out.txt` | Fixed read-only recipes using built-in actions only; **no App Intents**. One click per recipe. `anyone` goes through iCloud. Nothing works while the Mac is asleep |
| [sweetrb/apple-notes-mcp](https://github.com/sweetrb/apple-notes-mcp) | 133 | 2025-12-27 / 2026-09-25 | AppleScript plus a read-only NoteStore DB, plus 3 generated, signed shortcut bridges that call Notes App Intents; `shortcuts run <UUID> --input-path <tmp JSON>`; verifies by reading state back | Notes only. One Add click per bridge. **A foreground "Always Allow" run is needed after every install or upgrade**, or background runs stall |
| [viticci/shortcuts-playground-plugin](https://github.com/viticci/shortcuts-playground-plugin) | 1,126 | 2026-04-14 / 2026-06-15 | Agent skill that writes, validates and signs shortcuts; the user imports them | Doesn't run anything or serve MCP. Third-party intents have no schemas. The author estimates about 90% correct |
| [recursechat/mcp-server-apple-shortcuts](https://github.com/recursechat/mcp-server-apple-shortcuts) | 349 | 2024-12-11 / 2024-12-22 | `shortcuts list`, then `shortcuts run "<name>" -i "<input>"` through a shell string | Command injection (issue #9). Text passed as a path. Only existing shortcuts. Stale |
| [artemnovichkov/shortcuts-mcp-server](https://github.com/artemnovichkov/shortcuts-mcp-server) | 32 | 2025-05-11 / 2026-09-10 | Swift: `shortcuts list/run/view` | No input parameter; text output; only existing shortcuts |
| [foxtrottwist/shortcuts-mcp](https://github.com/foxtrottwist/shortcuts-mcp) | 11 | 2025-07-28 / 2026-05-04 | AppleScript via "Shortcuts Events" | Only existing shortcuts; the user must add Stop and Output; no schema |
| [pricemi115/RunShortcutsMCP](https://github.com/pricemi115/RunShortcutsMCP) | 0 | 2026-07-25 / 2026-09-05 | Swift; `shortcuts run` with stdin; default-deny allowlist; async jobs | Only allowlisted existing shortcuts |
| [eneko-codes/apple-shortcuts-mcp](https://github.com/eneko-codes/apple-shortcuts-mcp) | 0 | 2026-08-15 / 2026-09-07 | Swift; ScriptingBridge Apple events to Shortcuts Events | Can't create shortcuts; fixed 120 s timeout; shortcuts that wait for UI never finish |
| [loganprit/shortcuts-mcp](https://github.com/loganprit/shortcuts-mcp) | 1 | 2026-01-21 / 2026-09-06 | Reads `Shortcuts.sqlite` and scans `extract.actionsdata` for a catalog; runs via Shortcuts Events or a `shortcuts://` URL | Needs Full Disk Access; only existing shortcuts |
| [supermemoryai/apple-mcp](https://github.com/supermemoryai/apple-mcp) | 3,127 | 2025-02-19 / 2025-08-11 | Hand-written AppleScript per app; Messages read through `chat.db` | **Archived.** Open issues report false successes (#66) and searches failing |
| [steipete/macos-automator-mcp](https://github.com/steipete/macos-automator-mcp) | 885 | 2025-05-15 / 2026-09-13 | Arbitrary AppleScript or JXA | **Archived.** Runs arbitrary code; no App Intents |
| [mpociot/claude-siri-ai](https://github.com/mpociot/claude-siri-ai) (adjacent) | 220 | 2026-09-14 / 2026-09-15 | The reverse direction: Claude as a Siri model-delegation provider | Private entitlement; SIP and AMFI off |

**Gap intents-mcp fills.** No shipping project does *index every installed App Intent → generate a typed wrapper per chosen intent → sign it → serve it as an MCP tool with a JSON Schema built from the metadata*.
- The closest pieces are the Notes-only bridges in sweetrb/apple-notes-mcp (proof that the route works), Dominic-DK's install flow (sign, open, click, run by UUID), and Action Relay's metadata-to-tool mapping (on the private route).
- Viticci's issue #17 shows the Shortcuts Playground author is considering the same metadata source.

---

## 5. The official Swift MCP SDK

[modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk), checked with `gh api`:

- **Status:** 1,498★. Latest tag **0.12.1 (2026-05-07)**; no release since. License: MIT for existing code, Apache-2.0 for new contributions.
- **Package:** `swift-tools-version:6.1` (with a 6.0 fallback manifest). Platforms `.macOS("13.0")` and up. Dependencies: swift-system, swift-log, mattt/eventsource, and swift-nio (conformance executables only).
- **Spec versions:** `Sources/MCP/Base/Versioning.swift` has `supported = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]` and `latest = supported.max()!`, which is `2025-11-25`.
  - The current spec is **2026-07-28**: `modelcontextprotocol.io/specification/latest` returns a 307 to `/specification/2026-07-28`.
  - That spec removes the `initialize` handshake. Per its versioning page, legacy stdio servers still work with "dual-era" clients, which probe and then fall back to `initialize`.
- **Stdio server: supported.** `let transport = StdioTransport(); try await server.start(transport: transport)`.
  - Tools API: `Tool(name:title:description:inputSchema: Value, annotations:, outputSchema:)`. `Tool.Annotations` has `readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint`.
  - `CallTool.Result(content:structuredContent:isError:)`.
- **Pitfalls:**
  - The README's `.text("…")` shorthand is deprecated.
  - The README's `inputSchema` examples leave out `"type": "object"`.
  - Its logging example writes to stdout, which breaks stdio. Log to stderr.
- **Open issues that matter:**
  - **#287** (Codex `experimental` objects break `initialize`; fixes in PRs #276 and #289).
  - #262 (the same with ChatGPT).
  - #263 (`StdioTransport.send()` can interleave frames under backpressure; fix PR #266 open).
- **A test build worked.** A throwaway package pinned to `exact: "0.12.1"` resolved and built in about 25 s. The 5.1 MB release binary was `adhoc,linker-signed` and had no quarantine attribute [local, scratchpad only].
- **Decision needed:** vendor or fork the SDK with #276 applied, or write a small hand-rolled JSON-RPC stdio server. Either way, test against current Claude Code, Claude Desktop and Codex before launch.

---

## 6. Apple and native MCP support

| Date | What | Source |
|---|---|---|
| 2025-09-22 | 9to5Mac: "Apple is laying the groundwork to bring MCP support to App Intents", but "very incipient MCP support" | https://9to5mac.com/2025/09/22/macos-tahoe-26-1-beta-1-mcp-integration/ |
| 2026-02-03 | Xcode 26.3 exposes Xcode through MCP (`xcrun mcpbridge`); the docs give `claude mcp add … xcrun mcpbridge` and `codex mcp add …` | https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode ; https://www.macrumors.com/2026/02/03/xcode-26-3-agentic-coding/ |
| 2026-06 (WWDC26) | "What's new" App Intents items: SyncableEntity, LongRunningIntent, UndoableIntent, `supportedModes`, `allowedExecutionTargets`, and others. **No MCP** in App Intents, Siri or Shortcuts sessions. MCP appears only in session 382 (Xcode plugins "can contain MCP tools") | https://developer.apple.com/documentation/updates/appintents ; https://developer.apple.com/videos/play/wwdc2026/382/ |
| 2026-07-01 / 09-17 | Safari MCP server, `safaridriver --mcp`: "runs entirely on your local machine" | https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/ ; https://webkit.org/blog/18325/webkit-features-for-safari-27-0/ |
| Xcode 27 | Agent plugins with MCP servers, `xcrun mcp-server`, and "LLDB now ships with an MCP server" | https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes |
| 2026-09-14 | Siri model delegation to Claude or ChatGPT is in code; "Apple has not yet opened up the model delegation entitlement to third parties" | https://www.macrumors.com/2026/09/14/siri-can-be-swapped-out-for-chatgpt-claude/ |
| macOS 27 release notes | App Intents, Shortcuts and Siri entries; **no MCP entry** | https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes |

**Local check [local].** `rg -a` over `dyld_shared_cache_arm64e*` found:
- **Safari WebDriver MCP:** `WDMCPService` and `WDMCPToolDefinition`. `safaridriver --help` lists `--mcp  Run as an MCP (Model Context Protocol) server using stdio transport`.
- **Private framework `GenerativeAgents`** (`com.apple.GenerativeFunctions.GenerativeAgents`): `MCPClient`, `MCPServerConfig`, `MCPServersConfig`, `MCPToolSet`, `ModelContextProtocol.ToolDefinition.InputSchema` and the string `mcpServers`. This is an OS-level MCP **client**; its purpose is unknown.
- **Nothing matched** `AppIntentsMCP`, `LN*MCP`, `MCP*Intent` or `WFMCP`.

**Conclusion.** As of 2026-09-25 there is **no public API** for an external MCP client to call third-party App Intents on macOS 27. The only public route is still Shortcuts (the `shortcuts` CLI, Shortcuts Events, or URL schemes).
- The **Sherlock risk** is real: the 2025 groundwork, an MCP client in the OS, and Siri delegation in code.
- Watch WWDC27 and the macOS 27.x betas. The one-pager's "move on" trigger applies.

---

## 7. Homebrew distribution, notarization and the $99 program

- **Formula vs cask.**
  - Open-source CLIs built from source belong in a formula. "Proprietary or platform-specific binary-only software belongs in a cask" ([Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae)).
  - Homebrew 5.0.0 deprecated casks without codesigning. Casks "that fail Gatekeeper checks" were due to be disabled in September 2026 ([Homebrew 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/); [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)).
- **Swift formula pattern (homebrew-core, read via gh):**
  - [`swiftformat.rb`](https://github.com/Homebrew/homebrew-core/blob/main/Formula/s/swiftformat.rb): `uses_from_macos "swift" => :build`; `system "swift", "build", *std_swift_args`; `bin.install ".build/release/swiftformat"`.
  - [`xcbeautify.rb`](https://github.com/Homebrew/homebrew-core/blob/main/Formula/x/xcbeautify.rb): uses `allow_network_access! :build` ("downloads swift packages during install"). This is the pattern needed for a SwiftPM dependency like the MCP SDK.
  - On macOS, `std_swift_args` expands to `--disable-sandbox --configuration release --jobs N`.
- **homebrew-core eligibility** ([Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy), read 2026-09-25):
  - 30 forks, 30 watchers or 75 stars.
  - **90 forks, 90 watchers or 225 stars for a self-submission.**
  - "A code repository less than 30 days old is normally not eligible."
- **Own tap:**
  - `brew tap-new <user>/homebrew-tap` sets up GitHub Actions bottling ([docs](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)).
  - Since Homebrew 6.0.0, non-official taps need trust. `brew install <user>/tap/intents-mcp` (fully qualified) "trusts only that item" ([Tap Trust](https://docs.brew.sh/Tap-Trust)).
- **Analytics.** Tap installs are public for non-private GitHub taps ([Analytics](https://docs.brew.sh/Analytics); `formulae.brew.sh/api/analytics/install/30d.json`). `steipete/tap/peekaboo` shows 963 installs in 30 days.
- **Apple side:**
  - On Apple Silicon every executable must be signed. The linker ad-hoc signs automatically, but such binaries "cannot pass through Gatekeeper" ([Big Sur 11.0.1 notes](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes)).
  - Gatekeeper checks quarantined downloads for Developer ID and notarization ([Apple Platform Security](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)).
  - A binary built by Homebrew from source, or a bottle, is not quarantined. Homebrew re-signs patched binaries ad-hoc.
  - Developer ID needs the Apple Developer Program: "you must be the Account Holder…" ([Developer ID](https://developer.apple.com/developer-id/)); "$99 annual membership" ([programs](https://developer.apple.com/programs/)). Notarization applies to "Developer ID-signed software" ([notarizing](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).

**What the $99/year program is actually needed for:**
- **Not needed** for:
  - a source-built formula or bottles in your own tap or homebrew-core;
  - `shortcuts sign`, which is an end-user Apple Account feature;
  - running the tool locally.
- **Needed only** to ship a **prebuilt binary that users download directly**: a GitHub-release tarball opened from a browser, a cask, a `.pkg`, a GUI `.app`, or an **MCPB bundle for Claude Desktop** if that path turns out to require Gatekeeper-clean binaries (unverified).
- **Correction to `one-pager.html`,** which says "Signing needs a $99/year Apple developer account". That is wrong for shortcut signing and for a Homebrew formula.

---

## 8. What this means for the build (inference)

1. **Indexer.**
   - Scan apps **and** `/System/Library` (PrivateFrameworks, ExtensionKit, CoreServices).
   - Resolve titles through `.loctable` and `Localizable.strings`.
   - Map framework actions to their host app.
   - Read the Team ID with `codesign -dv`.
2. **Default tool set.** Discoverable actions with background `supportedModes`, primitive or enum parameters, and an `outputType`: 129 on this Mac. Mark `DeleteEntity`-protocol actions as `destructiveHint` and leave them off by default.
3. **Entities.** Generate `find_<entity>` tools from `queries` and pass entity results between calls by identifier. How to rehydrate an entity inside a wrapper is **the key unknown**; see open questions 1–4.
4. **Runner.**
   - Call `shortcuts run <UUID> --input-path <tmp.json> --output-path <tmp.out> --output-type public.plain-text`.
   - Never inherit stdin.
   - Enforce a timeout. Check the exit code.
   - Treat "Couldn't find shortcut" as "the user has not imported it yet".
5. **Onboarding cost per tool.** One "Add Shortcut" click plus one foreground "Always Allow" run. Say this in the README. It is the main friction.
6. **Verification.** Follow sweetrb: read state back (for example, list notes after creating one) rather than trusting the wrapper's output.

## 9. Open questions that need a live experiment (GATE: needs the user's OK to create, sign, import and run test shortcuts)

1. Does `shortcuts sign --mode people-who-know-me` work offline or signed out of iCloud? Does the result import on the same Mac with "Private Sharing" off?
2. What is the minimal `AppIntentDescriptor`? Is `TeamIdentifier` needed? What does `ActionRequiresAppInstallation` do? Do Mac bundle IDs (`com.apple.Notes`) and iOS ones (`com.apple.mobilenotes`) both work?
3. Do framework-hosted intents need the host app's bundle ID (Reminders, Calendar)? Does the identifier match the ToolKit database for every third-party app on this Mac?
4. Can an entity parameter be filled from JSON (an ID string, or an `{identifier, displayString}` dictionary), or must a Find action always be chained?
5. Which consent prompts appear when `shortcuts run` is spawned by an MCP server under Claude Desktop, Claude Code and Codex? Does "Always Allow" survive re-importing an updated wrapper, and does re-import keep the UUID?
6. Stdin versus file input: does the input arrive as `WFGenericFileContentItem`? Does `detect.dictionary` parse it? What about large, non-ASCII or nested JSON?
7. Output: what comes out for AppEntity, array, file and dictionary results? Is a "Get Text" or JSON step needed before Stop and Output?
8. What happens on a wrong or missing parameter key for an App Intent: a default value, a stalled prompt, or exit code 1?
9. What is the latency per call (cold and warm)? What happens with `openAppWhenRun` intents under the CLI?
10. Does a signed wrapper cached for longer than about a year still import after its leaf certificate expires?

## 10. Blocked or unverified

- **WebSearch** hit the session limit (200/200) during the research. Some sources were reached only by direct URL, so newer reports may have been missed.
- **Not tested, because it was out of scope:** `shortcuts run` over SSH or with no GUI login, the `-o -` stdout behaviour, and signing while offline or signed out.
- **No macOS 27 SDK is installed,** so the public AppIntents interface for macOS 27 was not searched for MCP symbols.
- **Unverified:** whether Claude Desktop will run a non-notarized binary from an MCPB, and the exact meaning of the `supportedModes` bits and `typeIdentifier` codes.
