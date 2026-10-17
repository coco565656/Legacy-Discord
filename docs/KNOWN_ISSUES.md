# Known issues

Only reproducible issues belong here. Do not add remembered or suspected
problems without evidence.

## Reproduced issues

```text
Issue ID: LD-2026-032
Found: 2026-10-17
Priority: P3 (harness-only rendering artifact)
Screen: DevLocal member pane (member-* and channel-* fixtures with a member list)
Reproduction steps: Run capture-ui-dev.sh on a fixture that renders the member pane and inspect the right edge of the pane.
Reproduction rate: Visible in DevLocal fixtures at 720x520, 960x640 and 1280x800 before today's pass.
Expected result: A clean dark pane edge.
Actual result: A short stray vertical stub line near the top of the member pane.
Screenshot: artifacts/local-dev/screenshots/ (member pane fixtures; see regression runs)
Log: not required (no crash; rendering only)
Crash report: none
sample result: not required; the fixture exits normally.
Cause: not yet identified; the same pane is clean on real devices, so the artifact is limited to the DevLocal replay harness.
Fix commit: not scheduled
Regression test: none (harness-only)
Legacy OS status: NOT APPLICABLE (absent on Snow Leopard 10.6.8 rd-08 and Mountain Lion 10.8.5 real-device captures)
```

Other screens and untested operations are not certified bug-free.

## Resolved with regression evidence

```text
Issue ID: LD-2026-026
Found: 2026-10-17
Priority: P1 (emoji picker popup extends past the window edge and is clipped)
Screen: Emoji picker popup opened from the composer on Mac OS X 10.6.8 / 10.8.5
Reproduction steps: In a channel, click the composer emoji button so the popup opens toward the window's right edge.
Reproduction rate: 2/2 real-device captures before the fix (rd-11..rd-14); DevLocal composer-emoji-picker fixture shows the same overflow.
Expected result: The popup is fully inside the main window.
Actual result: The popup's right edge ran roughly 150 points past the window edge and the last grid columns were unreachable.
Before screenshot: artifacts/snow-leopard/screenshots/rd-14-emoji-down.png
Crash report: none
Cause: DLCompatibilityPopover clamped the panel's Y into the parent window content rect but clamped X only against the screen.
Fix: Clamp X into the parent window content rect (8-point inset) in fallbackOriginForRect:view:edge:, mirroring the existing Y clamp.
Regression test: Rebuilt and relaunched on both real devices: Snow Leopard rd-23-picker.png shows the popup at x 663-1003 inside the window (right edge 1011); Mountain Lion rd-m-03-picker.png shows the right edge at about 972 inside the window. Full local screenshot regression passed (60 captures).
Fixed screenshots: artifacts/snow-leopard/screenshots/rd-23-picker.png, artifacts/mountain-lion/screenshots/rd-m-03-picker.png
Legacy OS status: PASS on Snow Leopard 10.6.8 and Mountain Lion 10.8.5 real devices.
```

```text
Issue ID: LD-2026-027
Found: 2026-10-17
Priority: P1 (custom emoji grid mostly blank placeholder rows right after switching servers)
Screen: Emoji picker popup, custom emoji section
Reproduction steps: Switch to another server, then immediately open the emoji picker and inspect the custom emoji rows.
Reproduction rate: Seen in rd-11, rd-13 and rd-14 before the fix; every first open after a server switch.
Expected result: Emoji images are visible immediately, as in the official client.
Actual result: Many cells stayed at the "…" placeholder and only filled after repeated opens or scrolling.
Before screenshot: artifacts/snow-leopard/screenshots/rd-14-emoji-down.png
Crash report: none
Cause: Custom emoji images were downloaded one by one only when the picker displayed them; nothing warmed the HTTP cache when a server's channel list loaded.
Fix: Added +(void)prefetchEmojiImages: on DLEmojiPickerController (DLEmojiPrefetchHandler issues cached AsyncHTTPGetRequest downloads in the background) and call it from DLController channelsForServer: right after selectedServer is set.
Regression test: Rebuilt and relaunched on both real devices: Snow Leopard rd-23-picker.png shows the grid mostly populated on first open; Mountain Lion rd-m-03-picker.png shows the grid fully populated on first open with no placeholders. Full local screenshot regression passed (60 captures).
Fixed screenshots: artifacts/snow-leopard/screenshots/rd-23-picker.png, artifacts/mountain-lion/screenshots/rd-m-03-picker.png
Legacy OS status: PASS on Snow Leopard 10.6.8 and Mountain Lion 10.8.5 real devices. Very large emoji sets may still briefly show a few "…" cells while downloads finish; they fill via cacheDidUpdate.
```

```text
Issue ID: LD-2026-028
Found: 2026-10-17
Priority: P2 (right-click on embed cards and stickers shows no context menu)
Screen: Chat embed cards (title/description/media image) and sticker images in message rows
Reproduction steps: Right-click an embed image or embed title inside any channel.
Reproduction rate: 2/2 (rd-15 and rd-22); rd-22 re-confirmed on the live Snow Leopard device.
Expected result: The message context menu (reactions, reply, copy message link, delete, ...) opens.
Actual result: Only the hover action bar appeared; no menu opened at all.
Before screenshots: artifacts/snow-leopard/screenshots/rd-15-contextmenu.png, artifacts/snow-leopard/screenshots/rd-22-rclick-embedimg.png
Crash report: none
Cause: NSView_Events.rightMouseDown: forwards the event only to its own delegate; embed containers were plain NSBox, selectable NSTextField and NSImageView, which swallow right mouse down instead of forwarding it up to the message row that owns the menu.
Fix: Added DLForwardRightMouseDownToMessageRow() plus DLEmbedForwardingBox/TextField/ImageView in ChatItemViewController.m and applied them to embed cards, embed text fields, embed media images and sticker images; added the same forwarding on AttachmentPreviewViewController's eventHandlerView.
Regression test: Rebuilt and relaunched on both real devices: right-click on the earthquake embed map now opens the full message context menu (rd-25-embed-menu.png on Snow Leopard, rd-m-05-embedmenu.png on Mountain Lion).
Fixed screenshots: artifacts/snow-leopard/screenshots/rd-25-embed-menu.png, artifacts/mountain-lion/screenshots/rd-m-05-embedmenu.png
Legacy OS status: PASS on Snow Leopard 10.6.8 and Mountain Lion 10.8.5 real devices.
```

```text
Issue ID: LD-2026-029
Found: 2026-10-17
Priority: P2 (dates and timestamps ignore the in-app language setting)
Screen: Date dividers, <t:...> message timestamps and their tooltips, profile member-since metadata
Reproduction steps: Set the app language opposite to the system locale, then open a channel containing a date divider or a <t:...> timestamp.
Reproduction rate: Found by code inspection (all formatters used [NSLocale currentLocale]); the mismatch combination was replayed in DevLocal.
Expected result: Dates follow the app's language selection, consistent with all other UI strings.
Actual result: Formatters followed the system locale, so app language and date formats could disagree.
Before screenshot: none (found by code inspection of the three formatter call sites)
Crash report: none
Cause: The divider, timestamp and member-since formatters used the system currentLocale instead of the app language.
Fix: Added +(NSLocale *)localeForAppLanguage to DLLocalization (ja_JP or en_US from activeLanguage) and applied it to ChatItemViewController setDateDividerDate:, DLTextParser's <t:...> and tooltip formatters, and DLUserProfileController's member-since formatter.
Regression test: DevLocal replay with AppLanguage=ja shows the divider as 「2024 年 6 月 11 日」 (fix-locale-states.png); after restoring the default language the full local screenshot regression passed (60 captures). Mountain Lion real device shows Japanese dividers natively.
Fixed screenshots: artifacts/local-dev/screenshots/fix-locale-states.png, artifacts/mountain-lion/screenshots/rd-m-02-emoji.png
Legacy OS status: PASS on Mountain Lion 10.8.5 real device; the en-system/ja-app mismatch combination was verified in DevLocal replay only.
```

```text
Issue ID: LD-2026-030
Found: 2026-10-17
Priority: P3 (reply preview text overlaps the chat text column's right margin)
Screen: Message rows with a reply preview
Reproduction steps: Open a channel with replies and compare the reply preview text edge with the message text edge.
Reproduction rate: Visible in local baseline captures before the fix.
Expected result: The reply preview ends where the message text column ends.
Actual result: The reply preview extended about 19 points past the message text's right margin.
Before screenshot: artifacts/local-dev/regression/20261017-132011/screenshots/composer-reply-960x640.png
Crash report: none
Cause: The referenced-message frame used NSWidth(insetView bounds) - 5 while message text reserves a 16-point right margin.
Fix: Reserved 24 points instead of 5 when computing the referenced frame in ChatItemViewController.m.
Regression test: Full local screenshot regression passed (60 captures); the recaptured composer-reply-960x640 keeps the reply preview inside the message text column.
Fixed screenshots: artifacts/local-dev/regression/20261017-155834/screenshots/composer-reply-960x640.png, artifacts/local-dev/screenshots/fix-locale-states.png
Legacy OS status: PASS in DevLocal replay; real-device spot check rd-m-02-emoji.png shows no overlap.
```

```text
Issue ID: LD-2026-031
Found: 2026-10-17
Priority: P3 (image and video attachment previews have square corners)
Screen: Attachment previews in message rows
Reproduction steps: View a message with an image or video attachment.
Reproduction rate: Visible in every attachment capture before the fix.
Expected result: Corners match the official client's rounded attachment mask (about 8 points).
Actual result: Square corners over the message background.
Before screenshot: artifacts/local-dev/regression/20261017-132011/screenshots/channel-layout-attachment-960x640.png
Crash report: none
Cause: Attachment previews used plain NSImageView/WebView without a corner mask.
Fix: Added DLRoundedAttachmentImageView (rounded clip path, radius 8) for image previews and border-radius:8px for the video WebView.
Regression test: Build passed and the full local screenshot regression passed (60 captures). The local fixture image has a transparent background so the corners cannot be judged there; the radius change is code-verified only.
Fixed screenshots: artifacts/local-dev/screenshots/fix-attachment.png (background removed; corners not visually verifiable in DevLocal)
Legacy OS status: NOT VERIFIED (no image attachment available in the real-device test channels; behavior unchanged for non-attachment rows)
```

```text
Issue ID: LD-2026-023
Found: 2026-10-01
Priority: P1 (profile custom status unreadable on dark background)
Screen: Normal Release compact and expanded User Profile on Mac OS X 10.6.8
Reproduction steps: View a server member with a custom status; expand their card.
Reproduction rate: Visible in both recorded card and expanded profile before correction.
Before screenshots: artifacts/snow-leopard/20261001-ui-debug/other-profile-card.png, other-profile-expanded.png
Cause: The bubble draws nativeInputColor, but both status labels used a fixed dark 0.18 gray foreground.
Fix: Use nativePrimaryTextColor for status labels and explicitly configure multiline wrapping.
Regression test: Rebuilt and relaunched normal Release, reopened the same member card and expanded profile; status is readable in both. No user status was changed.
Fixed screenshots: artifacts/snow-leopard/20261001-ui-debug/other-profile-card-final.png, other-profile-expanded-final.png
Legacy OS status: PASS for the recorded Snow Leopard dark appearance checks; other appearances and OS versions NOT VERIFIED.
```

```text
Issue ID: LD-2026-024
Found: 2026-10-01
Priority: P1 (long profile metadata overlaps/clips below its row)
Screen: Normal Release compact and expanded User Profile on Mac OS X 10.6.8
Reproduction steps: View a member with joined date, pronouns and mutual-server metadata.
Reproduction rate: Visible in both recorded card and expanded profile before correction.
Before screenshots: artifacts/snow-leopard/20261001-ui-debug/other-profile-card.png, other-profile-expanded.png
Cause: Fixed-height single-row labels retained the NSTextField cell's wrapping behavior, so metadata flowed into a second clipped line above ROLES.
Fix: Default profile labels to one native line with tail truncation; preserve full metadata in tooltips. Explicitly retain multiline behavior for bio, custom status and activities/connections.
Regression test: Actual normal Release on Snow Leopard; same member's metadata stays inside its row in compact and expanded profiles; bio and connections retain multiple lines.
Fixed screenshots: artifacts/snow-leopard/20261001-ui-debug/other-profile-card-final.png, other-profile-expanded-final.png
Legacy OS status: PASS for the recorded Snow Leopard checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-022
Found: 2026-10-01
Priority: P1 (expanded User Profile remains on screen after clicking native close)
Screen: Normal Release expanded User Profile on Mac OS X 10.6.8
Reproduction steps: Open a user card, click its avatar to expand, then click the red native close button without editing the private note.
Reproduction rate: Reproduced in the live Release app left open by the user.
Before screenshot: artifacts/snow-leopard/20261001-ui-debug/profile-close-before.png
Runtime evidence: After the click, the User Profile panel reported isVisible=NO but parentWindow remained non-nil and the parent still had one child. Main thread sample showed a normal AppKit event loop, not a hang. No profile content or credentials were printed by the debugger.
Cause: Native window close did not remove the expanded panel from its parent's child-window list on Snow Leopard. The explicit controller close path did detach it, but native red-button close had no windowWillClose cleanup.
Fix: In windowWillClose, detach the expanded panel from its actual parent. Explicitly retain controller ownership across closes using setReleasedWhenClosed:NO. Preserve the existing unsaved-note confirmation.
Regression test: Actual normal Release on Snow Leopard; opened own profile, expanded and closed with red button, reopened and closed with Command-W. Repeated expansion/close for another member; compact card close also removes the panel. No private note was edited/saved.
Fixed screenshots: artifacts/snow-leopard/20261001-ui-debug/profile-closed-fixed.png, profile-reopen-command-close.png, profile-final-closed.png
Legacy OS status: PASS for the recorded normal Release Snow Leopard checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-021
Found: 2026-10-01
Priority: P1 (partial dates and excessively clipped authors in narrow message headers)
Screen: Normal Release channel with member list open at 747x524
Reproduction steps: Open member list and shrink the window, then expand to 960x640.
Reproduction rate: Visible in the recorded narrow screen before correction.
Before screenshot: artifacts/snow-leopard/20261001-ui-debug/rules-final-narrow.png
Cause: Header layout reserved up to 48 percent of available width for timestamps regardless of measured text width, producing partial dates and leaving little space for authors.
Fix: Show the full timestamp only when it fits alongside a measured minimum author width; otherwise give that space to the author. The author tooltip preserves full name and date. Recompute on every header layout.
Regression test: Actual normal Release on Snow Leopard shows readable author names without partial dates at 747x524; full dates return at 960x640. Native truncation remains intentional for long names.
Fixed screenshots: artifacts/snow-leopard/20261001-ui-debug/message-header-final-narrow.png, message-header-final-wide.png
Legacy OS status: PASS for these Snow Leopard checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-014
Found: 2026-10-01
Priority: P1 (Narrow message reactions disappear)
Screen: Normal Release channel with five existing reactions and member list open
Reproduction steps: Inspect the affected screen, then resize or change the split width where applicable.
Reproduction rate: Observed in normal Release before correction; not an exhaustive stress test.
Before screenshot: artifacts/snow-leopard/20261001-ui-debug/members-before.png
Cause: Button creation stopped at the first row width; row height reserved only one line.
Fix: Keep all buttons and lay out measured widths in wrapping rows; reserve their total height.
Regression test: Rebuilt normal Release, launched with existing session on actual Snow Leopard; read-only screen inspection at 747x524 and/or 960x640 as shown by the captures.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/rules-final-narrow.png
Crash report: none
Legacy OS status: PASS for the recorded Snow Leopard screen checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-015
Found: 2026-10-01
Priority: P1 (Channel title overlaps toolbar controls)
Screen: Normal Release channel header with the split divider moved right
Reproduction steps: Inspect the affected screen, then resize or change the split width where applicable.
Reproduction rate: Observed in normal Release before correction; not an exhaustive stress test.
Before screenshot: artifacts/snow-leopard/20261001-ui-debug/members-split-before.png
Cause: Independent autoresizing masks shrink the title without recomputing toolbar positions.
Fix: Recompute native control positions, search width and title width from header bounds.
Regression test: Rebuilt normal Release, launched with existing session on actual Snow Leopard; read-only screen inspection at 747x524 and/or 960x640 as shown by the captures.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/rules-final-narrow.png
Crash report: none
Legacy OS status: PASS for the recorded Snow Leopard screen checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-016
Found: 2026-10-01
Priority: P1 (Member pane has white scroller and overlaps chat)
Screen: Normal Release member list at wide and narrow widths
Reproduction steps: Inspect the affected screen, then resize or change the split width where applicable.
Reproduction rate: Observed in normal Release before correction; not an exhaustive stress test.
Before screenshot: artifacts/snow-leopard/20261001-ui-debug/members-before.png
Cause: Default Aqua scroller and fixed member width exceeded available host space.
Fix: Use themed auto-hiding scroller; derive member/chat/composer frames from host bounds on resize.
Regression test: Rebuilt normal Release, launched with existing session on actual Snow Leopard; read-only screen inspection at 747x524 and/or 960x640 as shown by the captures.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/rules-final-narrow.png
Crash report: none
Legacy OS status: PASS for the recorded Snow Leopard screen checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-017
Found: 2026-10-01
Priority: P1 (Hover action bar is clipped in narrow chat)
Screen: Normal Release channel hover actions with member list open
Reproduction steps: Inspect the affected screen, then resize or change the split width where applicable.
Reproduction rate: Observed in normal Release before correction; not an exhaustive stress test.
Before screenshot: artifacts/snow-leopard/20261001-ui-debug/members-split-after.png
Cause: A fixed three-reaction bar exceeded the clip view width.
Fix: Fit the quick-reaction count to available width while keeping Add Reaction and Reply visible.
Regression test: Rebuilt normal Release, launched with existing session on actual Snow Leopard; read-only screen inspection at 747x524 and/or 960x640 as shown by the captures.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/codex-release-hover-narrow.png
Crash report: none
Legacy OS status: PASS for the recorded Snow Leopard screen checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-018
Found: 2026-10-01
Priority: P1 (Native search fields do not accept input on 10.6)
Screen: Normal Release emoji picker search
Reproduction steps: Inspect the affected screen, then resize or change the split width where applicable.
Reproduction rate: Observed in normal Release before correction; not an exhaustive stress test.
Before screenshot: artifacts/snow-leopard/20261001-ui-debug/codex-final-picker-japan.png
Cause: Replacement NSSearchFieldCell initialized with initTextCell is not editable/selectable on 10.6; a native cell probe reproduced both flags as zero.
Fix: Explicitly enable editable/selectable after installing the replacement cell in emoji, sticker and message search fields. Live japan filtering verified in emoji picker.
Regression test: Rebuilt normal Release, launched with existing session on actual Snow Leopard; read-only screen inspection at 747x524 and/or 960x640 as shown by the captures.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/release-picker-search.png
Crash report: none
Legacy OS status: PASS for the recorded Snow Leopard screen checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-019
Found: 2026-10-01
Priority: P1 (Friends subtitle is covered and rows move on resize)
Screen: Normal Release initial Friends screen at 960x640 and 747x524
Reproduction steps: Inspect the affected screen, then resize or change the split width where applicable.
Reproduction rate: Observed in normal Release before correction; not an exhaustive stress test.
Before screenshot: artifacts/snow-leopard/20261001-ui-debug/release-friends-wide-before.png
Cause: Scroll height used the outer host height, 42 points larger than the Friends container; document geometry was not refreshed after resizing.
Fix: Size the scroll view from its own container and defer row/document refresh until autoresizing finishes; resize title/subtitle widths.
Regression test: Rebuilt normal Release, launched with existing session on actual Snow Leopard; read-only screen inspection at 747x524 and/or 960x640 as shown by the captures.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/friends-final-narrow.png
Crash report: none
Legacy OS status: PASS for the recorded Snow Leopard screen checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-020
Found: 2026-10-01
Priority: P1 (Window growth expands the channel sidebar beyond its limit)
Screen: Normal Release window resized from 747x524 to 960x640
Reproduction steps: Inspect the affected screen, then resize or change the split width where applicable.
Reproduction rate: Observed in normal Release before correction; not an exhaustive stress test.
Before screenshot: artifacts/snow-leopard/20261001-ui-debug/release-members-wide.png
Cause: Snow Leopard lacks the modern split holding-priority behavior used to retain sidebar width.
Fix: Provide an NSSplitView resize delegate that preserves current sidebar width, clamps it to 180..360 and leaves at least 320 points for chat; clamp restored frames too.
Regression test: Rebuilt normal Release, launched with existing session on actual Snow Leopard; read-only screen inspection at 747x524 and/or 960x640 as shown by the captures.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/rules-final-wide.png
Crash report: none
Legacy OS status: PASS for the recorded Snow Leopard screen checks; Lion and Mountain Lion NOT VERIFIED.
```

```text
Issue ID: LD-2026-011
Found: 2026-10-01
Priority: P2 (standard emoji picker glyphs missing on Snow Leopard)
Screen: Standard emoji picker fallback panel on Mac OS X 10.6.8
Reproduction steps: Launch the offline composer-emoji-picker fixture at 720x520 on Snow Leopard and capture the desktop.
Reproduction rate: 1/1 capture
Expected result: The emoji grid shows recognizable images for every supported standard emoji.
Actual result: Most emoji buttons show missing-glyph boxes, while the same real picker renders emoji on current macOS.
Screenshot: artifacts/snow-leopard/20261001-ui-debug/codex-emoji-picker-snow-offline-720x520.png
Current-macOS comparison: artifacts/local-dev/probes/20261001-composer-emoji-picker.png
Crash report: none
Cause: Standard emoji cells use Unicode strings as NSButton titles and depend on system font glyph coverage.
Fix: Shared DLTwemojiRenderer and bundled Twemoji 17.0.3 PNGs; Unicode Emoji 16 catalog with 3,781 entries. Messages, reactions, labels and picker share the renderer.
Regression test: Normal Release live picker on Snow Leopard shows images, scrolls through the complete catalog and filters japan; headless renderer check validates every catalog PNG, flags, skin tones, keycaps, ZWJ, attributes and Unicode round trip on current macOS and Snow Leopard.
Fixed screenshots: artifacts/snow-leopard/20261001-ui-debug/release-picker-search.png, codex-final-picker-tail.png
Legacy OS status: PASS on Snow Leopard for the live picker, channel labels and reactions; live composer insertion/sending and other OS versions remain untested.
```

```text
Issue ID: LD-2026-013
Found: 2026-10-01
Priority: P1 (stale channel title after switching servers)
Screen: Normal Release app on Mac OS X 10.6.8, with no channel selected in the newly opened server
Reproduction steps: Open a channel, then click another server icon without selecting a channel there.
Reproduction rate: 3/3 server selections in the production app
Expected result: The header describes the current state and does not name the previous channel or Friends screen.
Actual result: The header retained Friends or the previous server's channel title while the new server's channel list was shown.
Screenshots: artifacts/snow-leopard/20261001-ui-debug/server-1-production.png, server-2-production.png, server-3-production.png
Crash report: none
Cause: prepareForServerChange cleared message rows but left the chat header label and image untouched.
Fix: Clear the old image and show Select a channel when the server changes.
Regression test: Rebuilt and relaunched the normal Release app on Snow Leopard; the three visible servers now show Select a channel until a channel is selected.
Fixed screenshots: artifacts/snow-leopard/20261001-ui-debug/server-1-after-header-fix.png, server-2-after-header-fix.png, server-3-after-header-fix.png
Legacy OS status: PASS on Snow Leopard 10.6.8 for all three visible server selections; Lion and Mountain Lion remain untested for this change.
```

```text
Issue ID: LD-2026-012
Found: 2026-10-01
Priority: P1 (Friends screen right edge visibly clipped by an Aqua scrollbar)
Screen: Initial Friends/Home screen in the normal Release app on Mac OS X 10.6.8
Reproduction steps: Launch the normal Release app with an existing session and open the initial Friends screen.
Reproduction rate: 1/1 production capture before the fix
Expected result: The Friends list fills its dark pane without a white scrollbar band when all rows fit.
Actual result: A 15-point white Aqua scrollbar occupied the right edge of the Friends list despite no scrolling being needed.
Screenshot: artifacts/snow-leopard/20261001-ui-debug/friends-production-before.png
Crash report: none
Cause: DLDirectMessageController created a vertical NSScrollView scroller without auto-hide or the app's dark scroller class.
Fix: Enable auto-hide and install a theme-colored NSScroller_BGColor; apply the same color on theme changes.
Regression test: Rebuilt and relaunched the normal Release app on Snow Leopard, restored the existing session, and captured the same Friends screen. The white band is absent.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/friends-production-after-clean.png
Legacy OS status: PASS on Snow Leopard 10.6.8 for the normal Release Friends screen; Lion and Mountain Lion remain untested for this change.
```

```text
Issue ID: LD-2026-010
Found: 2026-10-01
Priority: P1 (profile note unreadable against the dark profile UI)
Screen: Expanded user profile on Snow Leopard
Reproduction steps: Launch profile-note at 720x520 on Snow Leopard and capture the desktop.
Reproduction rate: 1/1 before the fix
Expected result: The private note editor uses the active input and text colors.
Actual result: The note editor kept NSTextView's default white background and black text inside the dark profile panel.
Screenshot: artifacts/snow-leopard/20261001-ui-debug/codex-final-profile-note-720x520.png
Crash report: none
Cause: The programmatically created note scroll view and text view did not receive the app's theme colors.
Fix commit: pending user validation
Regression test: The Snow Leopard profile-note recapture shows a dark note editor with readable text; the current-macOS 48-capture quick screenshot regression passed.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/codex-recheck-profile-note-720x520.png
Legacy OS status: PASS for the Snow Leopard offline profile replay; live profile editing and other OS versions remain untested for this change.
```

```text
Issue ID: LD-2026-009
Found: 2026-10-01
Priority: P1 (sticker picker white scroller track and blank fallback)
Screen: Sticker picker fallback panel on Snow Leopard
Reproduction steps: Launch composer-sticker at 720x520 on Snow Leopard and capture the desktop.
Reproduction rate: 1/1 before the fix
Expected result: The picker scroll track matches its dark background, and unsupported sticker formats have a visible placeholder.
Actual result: A white vertical scroller track appeared; the sparkle-only placeholder was invisible on Snow Leopard.
Screenshot: artifacts/snow-leopard/20261001-ui-debug/codex-final-composer-sticker-720x520.png
Crash report: none
Cause: The picker used a default Aqua scroller and an emoji-only borderless button placeholder without an explicit readable text color.
Fix commit: pending user validation
Regression test: The Snow Leopard composer-sticker recapture shows a dark scroll track and a legible STICKER placeholder; the current-macOS 48-capture quick screenshot regression passed.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/codex-recheck-composer-sticker-720x520.png
Legacy OS status: PASS for the Snow Leopard offline sticker replay; live sticker selection and other OS versions remain untested for this change.
```

```text
Issue ID: LD-2026-008
Found: 2026-10-01
Priority: P1 (Snow Leopard main-window white scroller bands)
Screen: Server rail, channel pane, and chat pane in the offline replay
Reproduction steps: Build the current source on Mac OS X 10.6.8, launch channel-basic at 720x520, and capture the desktop through SSH.
Reproduction rate: 1/1 before the fix
Expected result: Each scroll track blends with its pane background.
Actual result: Three 15-point white bands appeared at the right edges of the server, channel, and chat scroll views.
Screenshot: artifacts/snow-leopard/20261001-ui-debug/channel-basic-720x520-screen.png
Diagnostics: artifacts/snow-leopard/20261001-ui-debug/channel-basic-720x520.json
Crash report: none
Cause: The main-window custom scrollers had no background color; their color setter also did not request a redraw.
Fix commit: pending user validation
Regression test: Snow Leopard desktop recaptures of channel-basic at 720x520 and 960x640 and channel-navigation at 720x520 show no white bands. The current-macOS 48-capture quick screenshot regression passed.
Fixed screenshot: artifacts/snow-leopard/20261001-ui-debug/codex-final-channel-basic-720x520.png
Legacy OS status: PASS for the Snow Leopard offline replay; live login and other OS versions remain untested for this change.
```

```text
Issue ID: LD-2026-007
Found: 2026-09-09
Priority: P1 (legacy channel-navigation clipping)
Screen: Channel outline on Snow Leopard with a mention badge
Reproduction steps: Launch channel-navigation at 720x520 on Snow Leopard and inspect the selected channel's right-aligned mention badge.
Reproduction rate: 2/2 captures before the fix
Expected result: The complete badge and count remain inside the visible channel pane.
Actual result: Snow Leopard's traditional vertical scroller reserved 15 points while the table cell drew using the wider document frame, clipping the badge at the clip-view edge.
Screenshot: artifacts/snow-leopard/20260909-phase1b-navigation/channel-navigation-720x520.png
Log: artifacts/snow-leopard/20260909-phase1b-navigation/run.log
Crash report: none
sample result: not required; the application remained responsive, wrote diagnostics, and exited normally.
Cause: Right-aligned cell content used cellFrame without intersecting it with the outline view's actually visible rectangle.
Fix commit: pending user validation
Regression test: channel-navigation is unchanged at all three current-macOS sizes (21/21 full-suite pixel match), and the Snow Leopard 720x520 recapture shows the full badge with row/text heights equal.
Legacy OS status: PASS for the Snow Leopard offline navigation replay; live-login channel switching and the remaining legacy OS matrix are pending
```

```text
Issue ID: LD-2026-006
Found: 2026-09-08
Priority: P1 (shared attachment row geometry defect)
Screen: Normal message row with an oversized image attachment
Reproduction steps: Capture channel-layout-attachment at 720x520, 960x640, and 1280x800 and compare expected_height with actual_height in sanitized diagnostics.
Reproduction rate: 3/3 sizes before the fix
Expected result: The model height and displayed row height are identical after the local image preview is applied.
Actual result: The scaled attachment height was fractional (215.6 points), and AppKit backing-pixel alignment expanded the displayed row by 0.5 point.
Screenshot: artifacts/local-dev/regression/20260908-183438/screenshots/channel-layout-attachment-720x520.png
Log: artifacts/local-dev/regression/20260908-183438/diagnostics/channel-layout-attachment-720x520.json
Crash report: none
sample result: not required; the application remained responsive and exited normally.
Cause: DLAttachment returned a fractional scaled height for oversized images while the rendered AppKit frames aligned to backing pixels.
Fix commit: pending user validation
Regression test: attachment dimensions are rounded to a whole point; all 18 current-macOS fixture/size combinations have matching row and text heights. Snow Leopard channel-layout-attachment at 720x520 reports row 309/309 and text 32/32.
Legacy OS status: PASS for the Snow Leopard offline attachment replay; real-login and the remaining legacy OS matrix are pending
```

```text
Issue ID: LD-2026-005
Found: 2026-09-08
Priority: P1 (same-path screenshot capture false failure)
Screen: DevLocal screenshot automation
Reproduction steps: Capture twice to the same output path quickly enough for both atomic PNG writes to receive the same one-second modification timestamp.
Reproduction rate: 2/2 consecutive runs before the fix
Expected result: The second atomic replacement is detected and the capture succeeds.
Actual result: capture-ui-dev.sh used the shell -nt timestamp test, which cannot distinguish same-second writes on the bundled macOS Bash/filesystem combination, and reported that the new PNG was never written.
Screenshot: artifacts/local-dev/regression/20260908-182911 and artifacts/local-dev/regression/20260908-183208
Log: the corresponding fixture capture logs in those regression directories
Crash report: none
sample result: not required; the application had written the PNG and exited normally.
Cause: File freshness was tested using coarse modification times instead of the file identity changed by the application's atomic write.
Fix commit: pending user validation
Regression test: capture-ui-dev.sh now records the previous inode and accepts only a newly created file or an inode replacement; repeated same-path capture and the full 18-capture run pass.
Legacy OS status: NOT APPLICABLE (DevLocal-only script)
```

```text
Issue ID: LD-2026-004
Found: 2026-09-08
Priority: P1 (screenshot regression nondeterminism)
Screen: DevLocal sequential fixture capture
Reproduction steps: Capture channel-basic at 720x520 repeatedly without waiting for the previous fixture process to terminate.
Reproduction rate: 2/2 consecutive runs before the fix
Expected result: Each capture begins after the previous fixture has saved its window state and exited.
Actual result: capture-ui-dev.sh returned as soon as the PNG appeared, allowing fixture processes to overlap and race NSSplitView window-state persistence; toolbar spacing varied between captures.
Screenshot: artifacts/local-dev/probes/composer-extraction/first.png and second.png
Log: terminal probe performed after regression run 20260908-144029
Crash report: none
sample result: not required; each application exited, but the next launch began before termination completed.
Cause: The script did not wait for the process launched by open(1) to exit.
Fix commit: pending user validation
Regression test: repeated same-path and full six-screenshot runs must produce stable captures without overlapping fixture processes.
Legacy OS status: NOT APPLICABLE (DevLocal-only script)
```

```text
Issue ID: LD-2026-003
Found: 2026-09-08
Priority: P1 (shared message rendering defect)
Screen: Normal message row
Reproduction steps: Open channel-basic or channel-message-states and inspect an edited message at 720x520, 960x640, and 1280x800.
Reproduction rate: 12/12 across the current-macOS and Snow Leopard captures
Expected result: The (edited) marker follows the rendered message content and wraps with it.
Actual result: A separate XIB text field anchored the marker to the far-right edge of the row.
Screenshot: artifacts/local-dev/regression/20260908-135755/screenshots/channel-basic-720x520.png
Log: artifacts/local-dev/regression/20260908-135755/logs/fixture-channel-basic-720x520.log
Crash report: none
sample result: not required; the application remained responsive and exited normally.
Cause: editedInfoLabel used independent right-edge autoresizing instead of the message text container.
Fix commit: pending user validation
Regression test: test-local-regression.sh --screenshots passed both fixtures at all three sizes; Snow Leopard channel-message-states passed at 720x520 with calculated and displayed row heights equal.
Legacy OS status: PASS for the offline replay; real-login validation pending
```

```text
Issue ID: LD-2026-001
Found: 2026-08-25
Priority: P1 (local regression fixture unavailable)
Screen: channel-basic fixture
Reproduction steps: Run ./scripts/test-local-regression.sh --quick after adding channel-message-states.
Reproduction rate: 2/2
Expected result: channel-basic writes its PNG and exits within the capture timeout.
Actual result: no PNG was written; the application stayed open.
Screenshot: not produced (expected output path is in regression fixture log)
Log: artifacts/local-dev/regression/20260825-115029/logs/fixture-channel-basic.log
Crash report: none
sample result: channel-basic.sample.txt showed the main thread waiting for events.
Cause: channel-basic had three message strings but the shared authors array had four entries.
Fix commit: pending user validation
Regression test: test-local-regression.sh includes channel-basic in full and quick runs.
Legacy OS status: NOT APPLICABLE (DevLocal-only code)
```

```text
Issue ID: LD-2026-002
Found: 2026-08-25
Priority: P1 (local screenshot capture unavailable with a relative output path)
Screen: DevLocal capture script
Reproduction steps: Run capture-ui-dev.sh with --output artifacts/local-dev/probes/example.png.
Reproduction rate: 2/2
Expected result: the PNG is saved beneath the repository artifact directory.
Actual result: no PNG was written because the launched GUI application's working directory did not resolve the relative output path.
Screenshot: not produced (capture output path was unresolved)
Log: terminal output from 20260825-125848 probe
Crash report: none
sample result: channel-basic-720x520.sample.txt showed the main thread waiting for events, not stalled.
Cause: capture-ui-dev.sh passed relative paths directly to open(1).
Fix commit: pending user validation
Regression test: test-local-regression.sh --screenshots uses absolute artifact paths; capture-ui-dev.sh now normalizes relative paths.
Legacy OS status: NOT APPLICABLE (DevLocal-only script)
```

```text
Issue ID: LD-2026-025
Found: 2026-10-16
Priority: P0 (no connectivity at all on AquaProxy networks)
Screen: any network operation (REST, Gateway, voice signaling)
Reproduction steps: On Mac OS X 10.6 with AquaProxy installed and set as the system HTTP/HTTPS proxy, launch the app and log in.
Reproduction rate: 2/2 (Snow Leopard 10.6.8 MacBook-Mid2007, Mountain Lion 10.8.5 MBP 2012)
Expected result: login, servers, DMs and the gateway connection work with AquaProxy left enabled.
Actual result (before fix): every TLS connection failed ("SSL connect error" cycles from the gateway, silent REST failures); only localhost reachability checks ran.
Screenshot: artifacts/snow-leopard/screenshots/20261017-083503-62669.png (after fix: full session)
Log: /tmp/AquaProxy.error.log on the test machine ("Failed to connect to upstream host gateway.discord.gg:443: dial tcp: lookup gateway.discord.gg: no such host") and /var/log/system.log (app side)
Crash report: none
Cause: the app never read the system proxy settings, so nothing pointed at 127.0.0.1:6531; separately, AquaProxy routes TLS 1.3 / ALPN-h2 clients (our bundled curl + OpenSSL 3) to passthrough mode, which makes AquaProxy itself resolve and dial the target host, so a broken system resolver also breaks the proxy path.
Fix commit: pending user validation (see docs/AQUAPROXY_HANDOFF.md for the full change list)
Regression test: manual on both remote machines; scripts/verify-source.sh covers transport-safety checks.
Legacy OS status: PASS on 10.6.8 and 10.8.5 with AquaProxy enabled (2026-10-17 real-device sessions; voice UDP still cannot traverse an HTTP proxy)
```

## Entry template

```text
Issue ID: LD-YYYY-NNN
Found: YYYY-MM-DD
Priority: P0 | P1 | P2 | P3
Screen:
Reproduction steps:
Reproduction rate:
Expected result:
Actual result:
Screenshot:
Log:
Crash report:
sample result:
Cause:
Fix commit:
Regression test:
Legacy OS status: NOT TESTED | PASS | FAIL
```
