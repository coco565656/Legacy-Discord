# Legacy Discord — Agent Development Rules

## 0-b. Language policy

- Reply to the user in **Japanese** — explanations, questions, progress updates, final reports, handover memos. English replies are a defect, not style.
- English is allowed (and preferred) for: code identifiers, code comments, commit messages, shell commands, log lines, and the field labels of `docs/KNOWN_ISSUES.md` templates (`Issue ID:` etc.). Entry body text may be Japanese.
- If a section of this file conflicts with the language policy, the policy wins for user-facing text only; all technical rules keep their exact wording and intent.

## 0. Read this before touching the code

This repository is a fork of Discord Lite and is being developed as a **native Cocoa/AppKit Discord client for legacy Intel Macs**.

Hard support boundary:

- Minimum: Mac OS X 10.6.8 Snow Leopard
- Primary target: Mac OS X 10.6.8 Snow Leopard
- Formal maximum target: OS X 10.8.5 Mountain Lion
- Mavericks 10.9.5: best effort only
- Production architecture: x86_64
- Production deployment target: 10.6

The project goal is:

> Reproduce the useful visual structure and behavior of the official Discord desktop/web client with lightweight native AppKit code that remains practical on Snow Leopard-era Macs.

This is **not** a browser-wrapper project.

Do not convert the application to Electron, CEF, a full Discord WebView, SwiftUI, or another modern UI stack. Do not raise the deployment target to make a problem disappear. Do not redirect development away from the user's requested roadmap.

The user request for the current task overrides speculative improvements. `docs/ROADMAP.md` is the project roadmap; do not independently start unrelated roadmap items.

---

# 1. Current priority: drive reproducible GUI bugs toward zero

Visible GUI defects are bugs, not optional polish.

The current development priority is:

1. P0 — crash, startup/login failure, data loss, core feature unusable
2. P1 — severe layout/rendering/scrolling defect
3. P2 — incorrect message/Unicode/emoji/content rendering
4. P3 — mismatch from verified official Discord UI/UX
5. P4 — settings/theme/DM completeness requested by the user
6. P5 — minor animation or decorative polish

Do not spend substantial time on P5 while known P1/P2 defects remain.

The long-term target is **zero known reproducible GUI defects**, but never claim “bug-free” without extensive evidence.

Examples of GUI bugs that must be treated seriously:

- clipped or missing text
- overlapping views
- wrong row height
- wrong line height
- incorrect text baseline
- incorrect padding or margins
- controls outside their container
- broken autoresizing
- broken narrow/wide window layouts
- stale hover/action views
- disappearing views after reload
- incorrect scroll position
- new-message scroll jumps
- missing glyph boxes
- emoji changing line height unexpectedly
- wrong avatar/icon aspect ratio
- inconsistent theme colors
- broken selected/hover/unread states
- asynchronous image loading changing layout incorrectly

---

# 2. Do not drift from the project direction

The following are prohibited unless the user explicitly requests them:

- replacing AppKit with a web UI
- embedding the full Discord website
- modernizing merely for modernization
- raising the minimum macOS version
- removing Snow Leopard fallbacks
- rewriting networking/protocol code during an unrelated GUI task
- implementing voice/video/screen sharing while the task is GUI cleanup
- large speculative architecture rewrites
- replacing working native controls merely because a modern framework would be easier
- inventing unrelated features

Preserve working login, Gateway, REST, Keychain, channel loading, message send/receive, reconnect, attachments and existing native behavior while changing UI.

Do not discard or revert unrelated local changes.

---

# 3. Understand the actual UI ownership before editing

This repository mixes XIB-owned views and programmatically created views. **Never assume the XIB is the source of truth.** Determine who creates and who finally lays out the view before editing.

Important current ownership map:

## Main application UI

Primary files:

- `Discord Lite/DLMainWindowController.h`
- `Discord Lite/DLMainWindowController.m`
- `Discord Lite/en.lproj/DLMainWindowController.xib`
- `Discord Lite/DLMainWindowChromeControls.h/.m`
- `Discord Lite/DLMessageComposerControls.h/.m`
- `Discord Lite/DLServerNavigationController.h/.m`
- `Discord Lite/DLChannelNavigationController.h/.m`
- `Discord Lite/DLMessageReadStateController.h/.m`
- `Discord Lite/DLMemberListController.h/.m`
- `Discord Lite/DLUserProfileController.h/.m`
- `Discord Lite/DLThreadController.h/.m`
- `Discord Lite/DLMessageSearchController.h/.m`
- `Discord Lite/DLPinsController.h/.m`
- `Discord Lite/DLEmojiPickerController.h/.m`
- `Discord Lite/DLStickerPickerController.h/.m`
- `Discord Lite/DLMessageComposerController.h/.m`
- `Discord Lite/DLDirectMessageController.h/.m`
- `Discord Lite/DLMessagePresentationController.h/.m`
- `Discord Lite/DLMainHeaderController.h/.m`

`DLMainWindowController` is the main-window composition root and coordinator. It
creates the feature controllers, routes application callbacks to them, and
coordinates server/channel/screen transitions. Do not return feature state,
table/outline data sources, text-view behavior, message rendering, or detailed
toolbar behavior to this class.

Do **not** rewrite `DLMainWindowController` wholesale. Integrate incrementally and preserve existing behavior.

The small draw-only classes for the main split view, search field, connection
indicator, member/pin buttons, composer background, and composer emoji/sticker
buttons live in the two control files above. Server-table ownership, server
model delegates, and server-row drawing belong to
`DLServerNavigationController`. Channel-tree ownership, outline delegates,
channel model delegates, and channel-row drawing belong to
`DLChannelNavigationController`. Unread/history banner state, read
acknowledgement, and jump-to-latest behavior belong to
`DLMessageReadStateController`.

Keep cross-screen server/channel selection orchestration in
`DLMainWindowController`, but do not move these extracted data sources,
delegates, caches, notification observers, or row behavior back into it. New
main-window responsibilities should continue to leave the controller through
small, testable ownership boundaries rather than categories that preserve the
same owner.

## Message rendering

Primary files:

- `Discord Lite/ChatItemViewController.h/.m`
- `Discord Lite/en.lproj/ChatItemViewController.xib`
- `Discord Lite/DLTextParser.h/.m`
- `Discord Lite/ChatScrollView.h/.m`
- `Discord Lite/DynamicScrollView.h/.m`
- `Discord Lite/NSTextField+DynamicHeight.h/.m`
- `Discord Lite/PaddedTextView.h/.m`

Treat these as shared rendering infrastructure. A defect visible in many messages should be fixed here rather than patched individually in `DLMainWindowController`.

## Emoji picker

The standard/custom emoji picker is built programmatically by
`DLEmojiPickerController`. Composer integration belongs to
`DLMessageComposerController`; reaction selection is forwarded through that
same owner. Do not put picker state or construction back in
`DLMainWindowController`.

The current `standardEmojiPickerItems` is a small hard-coded Unicode list. It is not an acceptable final emoji catalog for Snow Leopard.

## User Settings

Primary files:

- `Discord Lite/DLPreferencesWindowController.h/.m`
- `Discord Lite/DLPreferencesHandler.h/.m`
- `Discord Lite/en.lproj/DLPreferencesWindowController.xib`

Important: the current `DLPreferencesWindowController` hides the old XIB content and constructs most of the visible settings interface programmatically in `windowDidLoad`.

Therefore, do not edit only `DLPreferencesWindowController.xib` and assume the visible settings UI changed.

`DLUserSettings` is currently Discord user-settings/model data such as guild folders. **Do not confuse `DLUserSettings` with the local application preferences UI/persistence layer.** Local client settings belong in the `DLPreferencesWindowController` / `DLPreferencesHandler` path unless a deliberate architecture change is justified.

## Themes

Primary files:

- `Discord Lite/DLPreferencesHandler.h/.m`
- `Discord Lite/DLUtil.h/.m`
- theme-change handling in `DLMainWindowController.m`

The existing theme path is already partly centralized through `appearanceTheme`, `DLAppearanceThemeDidChangeNotification`, and `DLUtil native*Color` methods.

Extend this shared path. Do not hard-code theme colors independently inside every screen.

## Direct Messages

Primary files:

- `Discord Lite/DLDirectMessageChannel.h/.m`
- `Discord Lite/DLDirectMessageController.h/.m`
- `Discord Lite/DLChannelNavigationController.h/.m`
- high-level DM loading/selection coordination in `DLMainWindowController.m`

DM improvements must reuse shared message rendering wherever possible. Do not create an unrelated second message renderer for DMs.

## Compatibility UI

Primary files:

- `Discord Lite/DLCompatibilityPopover.h/.m`

Use this existing abstraction where a native popover exists on Lion+ but Snow Leopard requires the AppKit panel fallback.

---

# 4. Mandatory GUI debugging method

Never use this workflow:

> look at screenshot → guess x/y constant → edit → guess another constant → declare fixed

Use this workflow:

> reproduce → identify owner → instrument → find first wrong value → fix root cause → build → capture → compare → regression test

For every significant GUI defect:

1. Reproduce it deterministically if possible.
2. Record the relevant window size.
3. Identify the complete view/controller path.
4. Determine whether the view is XIB-created or programmatic.
5. Determine who writes its frame last.
6. Inspect parent frame, child frame, text metrics, row height and scroll geometry.
7. Add temporary diagnostics if necessary.
8. Find the earliest incorrect value/assumption.
9. Fix that source, not a downstream symptom.
10. Build and rerun.
11. Compare the whole affected screen, not just the original pixel.
12. Test resizing and scrolling.
13. Run regression fixtures.
14. Remove temporary debugging hacks unless useful as permanent diagnostics.

If two or three variants of the same fix fail, **stop changing constants**. The hypothesis is probably wrong.

Re-check:

- a second layout pass
- autoresizing masks
- XIB constraints/frames
- cell reuse
- reload code
- asynchronous image callbacks
- font fallback
- text measurement
- flipped coordinates
- scroll/document-view geometry
- Snow Leopard-specific API behavior

---

# 5. Find the final writer before adding an offset

Before adding any permanent `x +=`, `y -=`, `height +=`, etc., search all code paths that can modify the same frame or content.

Typical searches include:

- `setFrame:`
- `setFrameSize:`
- `setFrameOrigin:`
- `setAutoresizingMask:`
- reload/update methods
- resize callbacks
- image/cache callbacks
- view reuse/update code

A child offset must not compensate for a broken parent calculation.

Magic offsets require a clear layout reason.

---

# 6. Text measurement must equal text rendering

When text clips, wraps incorrectly, or changes row height, first verify that measurement and drawing use the same:

- font
- font size
- attributes
- available width
- wrapping mode
- line spacing
- attachment dimensions
- display scale

Do not add arbitrary vertical padding to hide a font-metric or attributed-string bug.

Test at minimum:

- empty/very short text
- long multiline text
- long unbroken text
- English
- Japanese
- mixed Japanese/English
- mentions
- links
- edited markers
- replies
- reactions
- attachments
- Unicode emoji
- custom emoji

---

# 7. Use the existing diagnostics instead of guessing

`DLUIDiagnostics` already supports sanitized UI state including view hierarchy, message metrics, expected/actual message heights, display scale and theme.

Use and extend it when useful.

Diagnostics must never dump private Discord content, credentials, tokens, server names, channel names, usernames or other unnecessary personal data.

When a row-height bug exists, compare calculated and displayed height rather than judging only by eye.

---

# 8. DevLocal replay is the primary autonomous GUI test path

The repository already provides a current-macOS preview/replay environment. Use it aggressively for autonomous GUI work.

Useful commands:

```sh
./scripts/local-build-all.sh
./scripts/test-local-regression.sh --quick --screenshots
./scripts/test-local-regression.sh --screenshots
./scripts/local-run-dev.sh --fixture channel-basic
./scripts/capture-ui-dev.sh channel-basic --window-size 720x520
```

Existing deterministic screenshot sizes are:

- 720x520
- 960x640
- 1280x800

Current replay fixtures include:

- `channel-basic`
- `channel-message-states`
- `channel-layout-text`
- `channel-layout-unbroken`
- `channel-layout-states`
- `channel-layout-attachment`
- `channel-navigation`

These fixtures use the real shared message/controller/layout path. Preserve that property.
The attachment replay also uses the normal attachment model and preview
controller, with only the image bytes supplied locally. The navigation replay
supplies fictional server/channel models to the production server and channel
navigation controllers; it does not duplicate their tables, outline, cells, or
layout.

Do not create a visually convenient fake test window that bypasses the production rendering path and then use it as proof that production UI works.

---

# 9. Expand fixtures when a screen becomes important

The current test weakness is insufficient replay coverage outside message rows.

When implementing or heavily modifying these areas, add deterministic test coverage using the real production view/controller path where practical:

- Direct Messages
- emoji picker
- User Settings
- channel navigation with many channels/categories
- message hover/action bar
- input/editor states
- attachments/replies/reactions combinations

A new fixture must not duplicate the UI in hand-built test-only code. It should supply deterministic data/state to the real UI.

For Settings and emoji picker, expose a deterministic DevLocal route that opens the actual production controller/picker and captures it.

For DMs, drive the actual `DLMainWindowController` + DM source-list path with synthetic data rather than creating an independent DM mock window.

---

# 10. Screenshot comparison is required for visual work

For visual changes, compare at least the affected screen at all relevant deterministic sizes.

Inspect:

- pane widths
- relative spacing
- baselines
- clipping
- scrollbars
- composer alignment
- selected states
- image sizes
- hover states when testable
- theme consistency

Do not fix only the specifically reported defect if the resulting screenshot contains an obvious regression caused by your change.

A successful compiler exit is not visual verification.

---

# 11. `KNOWN_ISSUES.md` is evidence-based

Only reproducible defects belong in `docs/KNOWN_ISSUES.md`.

When adding an issue, preserve the existing evidence-oriented format:

- issue ID
- priority
- screen
- reproduction steps
- reproduction rate
- expected result
- actual result
- screenshot/log/sample/crash evidence
- cause when known
- fix status
- regression test
- legacy OS status

Do not fill the document with remembered, speculative or “probably broken” issues.

Do not remove an issue merely because a code change looks plausible. Require regression evidence.

---

# 12. Snow Leopard is the compatibility baseline

The production app must remain compatible with Mac OS X 10.6.8 x86_64.

A current-macOS DevLocal success does **not** prove legacy compatibility.

Do not change production build assumptions without explicit user approval, especially:

- `ARCHS = x86_64`
- `MACOSX_DEPLOYMENT_TARGET = 10.6`
- production non-ARC/manual-retain-release path
- legacy SDK/toolchain expectations

Before introducing an AppKit/Foundation/Security/WebKit API, verify 10.6 availability or provide an explicit runtime-safe fallback.

Existing examples of the correct compatibility style:

- `DLCompatibilityPopover`: Lion+ native popover, Snow Leopard AppKit panel fallback
- runtime selector checks for later APIs
- pre-Lion generic-password Keychain APIs

Do not “solve” a bug by making 10.7 or 10.8 the minimum.

---

# 13. Legacy Objective-C rules

Production source must remain buildable by the project's legacy toolchain.

Avoid introducing syntax/library assumptions that require a modern compiler or runtime when an equivalent legacy-compatible implementation exists.

Respect manual memory management in the production target.

When adding retained objects, review ownership, release paths and notification observers.

Do not introduce modern APIs merely because DevLocal on a current Mac accepts them.

---

# 14. Real-device status must remain honest

Formal compatibility is not complete until the same 10.6-targeted x86_64 artifact is tested on the formal legacy targets.

When a task cannot be run on a legacy machine, report:

> LEGACY OS REQUIRED / NOT VERIFIED

Do not convert current-macOS fixture success into a Snow Leopard PASS.

Use `docs/QA_CHECKLIST.md`, `docs/REAL_DEVICE_TESTING.md`, and `docs/SNOW_LEOPARD_COMPATIBILITY.md` as the status boundary.

---

# 15. Official Discord UI must be researched, not remembered

For any task whose goal is “make it like Discord”, **internet verification is mandatory when internet access is available**, unless the user explicitly provides the exact reference and asks to match that version.

Never make design decisions from model memory such as:

> Discord probably has this button here.

Instead:

1. identify the exact screen/feature being changed
2. find current official Discord desktop/web references
3. prefer official Discord documentation/support screenshots where useful
4. supplement with recent reliable screenshots/references when necessary
5. verify the date/version/context
6. compare with the current Legacy Discord screen
7. implement the closest practical native equivalent

For every substantial Discord-UI task, report what references were actually consulted.

If current references disagree or cannot be verified, say so. Do not invent certainty.

The official Discord UI is the **visual/interaction reference**. The implementation remains native AppKit.

---

# 16. Do not blindly copy modern Discord complexity

The goal is not to reproduce Electron internally.

Priority when approximating official Discord:

1. correct function
2. correct information hierarchy
3. correct layout
4. correct interaction
5. correct typography/spacing/colors
6. low-cost visual effects
7. animation

If an official effect is unnecessarily expensive on Snow Leopard-era hardware, reproduce its static appearance or use a cheaper native equivalent.

Do not add continuous animations, excessive timers, repeated full-view redraws, or unnecessary image decoding just for cosmetic parity.

---

# 17. Unicode emoji must not use Snow Leopard's system emoji rendering

This is a hard requirement.

Snow Leopard does not provide the Unicode emoji environment expected by modern Discord. Standard Unicode emoji must render through **Twemoji (or the exact project-approved Twemoji asset set)** rather than depending on Apple Color Emoji/system glyph fallback.

The user-visible result must not contain missing-glyph boxes merely because the OS lacks that emoji glyph.

Twemoji applies to Unicode emoji displayed in relevant Discord surfaces, including:

- message body
- reactions
- emoji picker
- replies
- usernames/nicknames when emoji is present
- status/presence text when emoji is present
- embeds/previews where rich text is used
- other Discord text surfaces that support emoji

---

# 18. Build one shared Unicode/Twemoji pipeline

Do not implement a different emoji parser in every screen.

The existing custom Discord emoji path in `DLTextParser` already converts `<:name:id>` / `<a:name:id>` content into `NSTextAttachment` images when data is available.

Use that architectural lesson, but keep Unicode Twemoji and Discord custom emoji logically distinct.

Preferred logical pipeline:

```text
Discord text
  -> legacy-safe text/emoji sequence parsing
  -> Unicode emoji sequence lookup
  -> Twemoji asset lookup
  -> NSTextAttachment / native attributed-text rendering
```

Custom Discord emoji remains:

```text
<:name:id> / <a:name:id>
  -> Discord emoji ID
  -> cached Discord CDN asset
  -> NSTextAttachment
```

Do not convert ordinary Unicode emoji into Discord custom-emoji markup.

Do not send image markup in the message payload. The logical message remains Unicode text; only local rendering becomes Twemoji.

---

# 19. Do not put the Twemoji engine inside `DLMainWindowController.m`

`DLMainWindowController.m` is already very large.

New reusable emoji responsibilities should be separated cleanly, for example:

- emoji sequence/catalog data
- Twemoji asset-name resolution
- Twemoji image loading/cache
- attributed-string replacement

The exact class/file names may follow project conventions, but the implementation must be reusable by `DLTextParser`, reactions and the picker.

Keep `DLMainWindowController` responsible for coordinating the picker, not for owning thousands of emoji definitions or the full parser.

---

# 20. Emoji parsing must handle sequences, not code units

Never assume:

> one UTF-16 character == one emoji

Support the Twemoji/Unicode catalog's complete sequences, including where applicable:

- variation selectors
- skin-tone modifiers
- zero-width-joiner sequences
- flags / regional indicators
- keycaps
- multi-codepoint families/professions

Do not depend on a modern `\p{Emoji}` regex/property implementation that is not guaranteed by Snow Leopard-era ICU/RegexKit.

Prefer a bundled, deterministic sequence/catalog representation generated from the chosen Twemoji/Unicode data and consumed by legacy-safe Objective-C code.

---

# 21. Twemoji assets must be legacy-safe and fast

Standard emoji rendering should not require a network connection.

Prefer locally bundled raster assets or another format proven to render correctly on 10.6. Do not assume modern SVG support.

Requirements:

- lazy-load where possible
- cache decoded images
- keep cache bounded/reasonable
- reuse image objects
- avoid decoding the same emoji during every redraw/scroll pass
- preserve transparent backgrounds
- include required Twemoji license/attribution

Do not make scrolling substantially heavier merely to support emoji.

---

# 22. Twemoji must behave like an inline glyph

Inline Twemoji must preserve:

- baseline alignment
- normal line height
- surrounding spacing
- wrapping
- selection behavior as far as practical
- message height calculation
- display scale

Test at minimum:

- 😀
- ❤️
- 👍
- 👍🏻
- 🇯🇵
- keycap sequence
- ZWJ sequence
- multiple consecutive emoji
- emoji at beginning/end
- Japanese + emoji
- multiline + emoji
- emoji-only message

If Discord-style larger emoji-only messages are implemented, make that an intentional shared rule rather than an accidental attachment-size side effect.

---

# 23. Replace the current hard-coded standard emoji picker catalog

The current `standardEmojiPickerItems` is only a small hand-written list and displays Unicode characters directly as native text.

That implementation must not be treated as complete.

Replace it with a data-driven catalog based on the chosen verified Discord/Twemoji emoji repertoire.

Requirements:

- cover the complete target emoji catalog rather than a small hand-picked set
- use Twemoji images in cells, not Snow Leopard font glyphs
- preserve the real Unicode sequence as the selected value
- support search aliases/keywords
- organize categories in a way based on verified current Discord UI where practical
- custom server emoji and standard Unicode emoji may appear in the same picker, but keep their data models distinct
- DM mode must correctly handle lack of server-specific custom emoji

When selected for message composition, insert the Unicode sequence into logical message text and render it locally through the shared Twemoji path.

---

# 24. Reactions must also stop depending on system emoji glyphs

A Unicode reaction such as 👍 must render with the same Twemoji asset system used by messages/picker.

Do not fix only the picker while leaving reaction summaries/buttons dependent on Snow Leopard fonts.

Custom reactions continue to use their Discord custom emoji asset.

Test add/remove/live update without message-row height corruption or attachment reload regressions.

---

# 25. User Settings: current placeholders are not the final design

The current programmatic settings UI contains temporary sections and “Coming soon” panes. Do not treat these as authoritative Discord settings structure.

Before redesigning User Settings:

1. research the current official Discord desktop User Settings UI
2. verify category names/order/structure
3. identify settings that this native client can actually support
4. implement real behavior and persistence for those settings
5. clearly omit or mark technically unsupported server-side features rather than creating fake functional controls

A visible control should work.

Do not create decorative settings that do nothing.

---

# 26. Gear button behavior

The current gear action opens an intermediate menu containing User Settings and Log Out.

Required direction:

- gear button opens User Settings directly
- remove the intermediate User Settings / Log Out popup
- move Log Out into User Settings
- preserve actual logout behavior and Keychain/session cleanup

When changing the action, update the actual wired target/action path. Do not leave dead popup code or a second conflicting settings entry path.

---

# 27. Settings persistence architecture

Use `DLPreferencesHandler` for local persistent client settings unless there is a strong reason to add a dedicated settings model.

Requirements for each local setting:

- current value is shown correctly
- changing it actually changes behavior
- state persists when appropriate
- state restores on relaunch
- UI updates immediately when practical
- Snow Leopard-compatible persistence APIs are used

Do not repurpose `DLUserSettings` merely because its name contains “Settings”; it currently represents Discord-side user settings/model data.

---

# 28. Theme architecture: extend the existing centralized path

The current local themes (`default`, `midnight`, `aurora`) are implementation history, not proof of the current official Discord theme catalog.

For the requested Discord/Nitro-like theme feature:

1. research the current official Discord appearance/theme UI
2. verify the current theme choices/content instead of remembering them
3. reproduce the applicable visual themes as closely as practical with native AppKit
4. keep the catalog/data separate from per-view drawing code

Use/extend the existing centralized path:

```text
DLPreferencesHandler appearanceTheme
  -> DLAppearanceThemeDidChangeNotification
  -> DLUtil native*Color / shared theme metrics
  -> views redraw/update
```

Do not hard-code a new theme by adding `if theme == ...` blocks throughout dozens of controllers.

If necessary, evolve the current palette functions into a clearer centralized theme object/catalog, but do so incrementally and preserve callers.

---

# 29. Official theme content must be verified at implementation time

Do not assume names, colors, gradients or Nitro availability from memory.

Discord changes these offerings.

Verify current official behavior online before implementing the theme list.

If a server-side Nitro entitlement cannot be reliably queried by this client, do not invent a fake entitlement check. Keep local visual implementation separate from entitlement logic and document any intentional divergence.

Performance on legacy hardware takes priority over reproducing expensive dynamic effects exactly.

---

# 30. Direct Messages must become a first-class Discord-style view

DM UI should converge toward verified official Discord desktop/web behavior while staying native.

Before changing DM layout, research the current official UI.

Inspect and improve the existing shared path rather than building a parallel application.

Relevant current pieces include:

- `DLDirectMessageChannel`
- `DLDirectMessageController`
- `DLChannelNavigationController` for the shared source-list rows
- high-level DM loading/selection coordination in `DLMainWindowController`
- shared `ChatItemViewController` conversation rows

Compare at minimum:

- DM list row layout
- avatars
- usernames/group names
- presence/status where supported
- unread/mention indicators
- selected state
- DM header
- conversation area
- composer
- group DM behavior when supported
- empty/home/friends/navigation state where applicable to the chosen reference

Do not break live unread/mention behavior that already works.

---

# 31. Native implementation, Discord visual reference

“Match Discord” does **not** mean “copy HTML/CSS”.

Use AppKit-native controls and drawing wherever practical:

- `NSOutlineView`
- `NSTableView`
- `NSScrollView`
- `NSTextView` / attributed strings
- native buttons/menus/panels
- project compatibility wrappers

Style/layout them to reproduce verified Discord information hierarchy and interaction.

The desired impression is:

> Discord running as a lightweight native legacy Mac application.

Not:

> a generic Aqua chat app

and not:

> Discord's website embedded in a window.

---

# 32. Centralize visual metrics

Where practical, shared values should come from one place:

- sidebar widths
- row heights
- avatar sizes
- icon sizes
- message spacing
- fonts
- font sizes
- colors
- corner radii
- separators
- composer metrics

Do not scatter unexplained constants through `DLMainWindowController.m`, XIBs and row controllers.

When a metric is intentionally screen-specific, make the reason clear.

---

# 33. Preserve scroll behavior during UI work

Discord is primarily a scrolling message client. Scroll regressions are high severity.

Test:

- initial channel load
- scrolling older/newer history
- new message while at bottom
- new message while reading older content
- own sent message
- channel switch
- DM switch
- resize while scrolled
- image/custom emoji cache update while scrolled
- reply/reaction row-height updates

Do not force the user to bottom when they are intentionally reading history.

---

# 34. Asynchronous image updates must not destabilize layout

Avatars, attachments, custom emoji, stickers and Twemoji may update views after initial layout.

When async/cached content arrives:

- avoid full unnecessary reloads
- preserve scroll position
- invalidate only what needs recalculation
- ensure expected and actual row heights converge
- avoid repeated network/cache requests
- avoid attachment preview reloads caused by unrelated reaction/emoji updates

---

# 35. Performance is a project feature

This client exists partly because modern Discord is impractical on the target systems.

Avoid:

- full-window redraw loops
- high-frequency polling
- unnecessary timers
- decoding identical emoji repeatedly
- unbounded image caches
- recreating the entire source list for tiny state changes when avoidable
- expensive transparency/animation effects without value
- network requests during offline fixture replay

Measure before performing a large optimization rewrite. Correctness remains first, but do not import modern-client overhead.

---

# 36. Test realistic content, not only “Hello World”

Every rendering change should be exercised with representative data:

```text
Short message
Very long wrapping message
verylongunbrokentext...
日本語メッセージ
English + 日本語 + 😀
😀 😃 ❤️ 👍🏻 🇯🇵
@mention
#channel
https://example.com
edited message
reply
Unicode reaction
custom emoji
attachment
embed
sticker where supported
```

Also test consecutive messages from the same author and compact/grouped rows.

---

# 37. Do not claim success without evidence

Allowed completion wording depends on what was actually tested.

Use:

- **Confirmed fixed** — reproduced before, tested after, evidence exists
- **Implemented, current-macOS regression passed** — DevLocal evidence only
- **Implemented but not visually verified** — no visual run was possible
- **LEGACY OS REQUIRED** — Snow Leopard/Lion/Mountain Lion behavior still needs real-device validation

Never say “Snow Leopard fixed” solely because the 10.6 deployment target compiles on a current Mac.

---

# 38. Required regression routine after meaningful GUI changes

At minimum, when the environment permits:

```sh
./scripts/local-build-all.sh
./scripts/test-local-regression.sh --quick --screenshots
```

For broad/shared rendering changes, run the full screenshot regression:

```sh
./scripts/test-local-regression.sh --screenshots
```

Inspect generated screenshots, not only the PASS exit code.

If the change affects a screen not currently covered, add/extend a real-path fixture before declaring the visual task comprehensively tested.

---

# 39. Real legacy build rules

Production/legacy verification follows the repository docs, not DevLocal assumptions.

Do not modify project-format/build settings automatically because a current Xcode recommends it.

Do not use current-Xcode 10.13 preview overrides as evidence for the formal 10.6 artifact.

When legacy verification is available, test the same production artifact on the formal supported OS versions as documented.

---

# 40. Internet research must not become scope drift

Research only what is needed to verify the Discord UI/behavior being implemented.

Do not use research as justification to add unrelated current Discord features.

If a current official UI contains features outside this project's requested scope, reproduce the relevant layout without automatically implementing every backend feature.

---

# 41. Keep a short hypothesis log for difficult bugs

For a GUI defect that takes multiple attempts, keep a concise working record:

```text
Observed:
...

Hypothesis 1:
...
Result: false / confirmed

Hypothesis 2:
...
Result: ...

Root cause:
...

Fix:
...

Regression evidence:
...
```

This prevents repeating disproven theories and endless coordinate tweaking.

It may remain only in the task notes unless it belongs in `docs/KNOWN_ISSUES.md`.

---

# 42. Avoid giant speculative refactors

Use the smallest coherent change that fixes the root cause.

A rewrite is justified only when evidence shows that:

- the current architecture fundamentally prevents correct rendering
- the current path depends on technology unavailable on 10.6
- repeated local patches have made behavior nondeterministic
- a shared component can eliminate multiple confirmed bugs safely

Before a major refactor:

1. list all callers
2. identify current working behavior
3. add regression coverage
4. refactor incrementally
5. compare behavior after each stage

---

# 43. Do not let `DLMainWindowController.m` become the dumping ground

Because the main controller already coordinates many features, new reusable logic should not automatically be added there.

Prefer extracting only genuine shared responsibilities, especially:

- Twemoji sequence/catalog handling
- reusable emoji image cache/renderer
- centralized theme catalog/palette
- reusable settings row/section helpers if repetition becomes substantial

Do not extract code merely to increase file count. The rule is: shared logic should have one owner; coordination remains in the controller.

---

# 44. Source of truth order

When assumptions conflict, use this order:

1. explicit current user instruction
2. reproducible behavior on the actual target OS
3. repository compatibility/QA documentation
4. verified current official Discord UI reference for visual behavior
5. regression fixture evidence
6. existing implementation
7. comments/model memory/assumptions

Existing code is not automatically correct merely because it is old.

Official Discord is not automatically implementable exactly merely because it is current; legacy compatibility and explicit user scope still apply.

---

# 45. Final report format for substantial UI tasks

At the end of a substantial GUI task, report concisely:

## Confirmed fixed

Only reproduced and verified items.

## Implemented / current-macOS verified

Changes whose DevLocal/current-macOS tests passed but still require legacy verification.

## Remaining known defects

Do not hide visible/reproducible defects.

## Regression evidence

List fixtures/sizes/commands actually run.

## Discord UI references

For Discord-matching work, list the important references actually consulted.

## Legacy compatibility status

State PASS only when genuinely tested on the applicable legacy OS; otherwise state `LEGACY OS REQUIRED`.

---

# 46. Task-specific direction currently requested by the user

Unless the user changes priorities, the intended UI direction includes:

1. aggressively reduce existing GUI/display bugs first
2. stop relying on system emoji and move standard Unicode emoji to Twemoji
3. replace the tiny standard emoji picker list with the complete chosen Discord/Twemoji catalog and Twemoji image cells
4. make User Settings structurally/functionally closer to verified official Discord
5. make the gear button open User Settings directly and move Log Out into Settings
6. implement a centralized Discord-like theme system based on verified current official theme offerings, including the requested Nitro-style theme content where technically practical
7. bring Direct Messages closer to verified official Discord desktop/web UI
8. keep all of this native, lightweight and Snow Leopard-compatible
9. do not guess what current Discord looks like; verify it online during implementation
10. do not derail into unrelated protocol/features while performing these UI tasks

These are project directions, not permission for a one-shot rewrite. Implement them incrementally with regression coverage.

---

# 47. Non-negotiable summary

Always remember:

> This is a native Discord Lite fork.

> Snow Leopard 10.6.8 is the baseline, not an afterthought.

> GUI correctness is functionality.

> The target is zero known reproducible GUI defects, not “looks acceptable on my machine.”

> Use the real production rendering path in tests.

> Do not guess at coordinates.

> Do not guess what Discord looks like.

> Research official Discord UI before imitating it.

> Unicode emoji must render through Twemoji rather than Snow Leopard's system emoji glyphs.

> Custom Discord emoji and Unicode Twemoji are separate data types but should share robust native rich-text infrastructure.

> Extend the existing centralized theme/settings paths instead of scattering hacks.

> The gear button should go directly to User Settings; Log Out belongs inside Settings.

> Direct Messages are a first-class UI.

> Do not turn this project into a web wrapper.

> Do not raise the deployment target.

> Do not claim a fix without evidence.

> Keep it native, lightweight, testable, and faithful to verified Discord UX.

---

# 48. Phase 1C ownership boundaries

The architectural source of truth is `docs/UI_ARCHITECTURE.md`.

Hard rules for future work:

- `DLMainWindowController` remains a coordinator and composition root.
- Server table state, rows and delegates belong to `DLServerNavigationController`.
- Channel/DM outline state, rows and delegates belong to `DLChannelNavigationController`.
- Composer text, reply, attachment, completion and typing state belongs to `DLMessageComposerController`.
- Emoji picker state belongs to `DLEmojiPickerController`.
- Sticker picker state belongs to `DLStickerPickerController`.
- Member-list and profile state must not return to `DLMainWindowController`.
- Search, Threads and Pins retain `DLMessageSearchController`, `DLThreadController` and `DLPinsController` as their owners.
- Friends/Home and DM presentation belongs to `DLDirectMessageController`.
- Message loading/presentation belongs to `DLMessagePresentationController`.
- Toolbar and connection presentation belongs to `DLMainHeaderController`.
- Guild, DM and replay messages share `DLMessage` -> `ChatItemViewController` -> `ChatScrollView`; never add a second renderer.
- Fixture code may change data supply and deterministic state only. It must not create a parallel UI or layout path.
