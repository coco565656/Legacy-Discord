# Real-device testing

Use only the dedicated test account while protocol compatibility is being
developed. Do not copy its token into source files or issue reports.

## Primary matrix

| Machine | OS | Priority |
| --- | --- | --- |
| 64-bit Intel test machine or VM | Mac OS X 10.6.8 | Primary (minimum) |
| 64-bit Intel test machine or VM | Mac OS X 10.7.5 | Primary |
| MacBook Pro 13-inch Mid 2012 | OS X 10.8.5 | Primary (maximum formal target) |
| MacBook Pro 15-inch Retina Mid 2012 | OS X 10.9.5 | Best effort |

## First smoke test

1. Create a private test server with two text channels and the test account.
2. Launch the client and sign in through the normal login form.
3. Confirm that the token appears in Keychain Access under
   `org.legacydiscord.client` and does not appear in Console logs.
4. Relaunch and confirm that the session resumes without another login.
5. Verify server and DM initial sync, message send/receive, reply, edit, delete,
   image upload, typing state and reconnect after Wi-Fi is toggled.
6. Log out and confirm the Keychain item is deleted.

## Snow Leopard screen captures

For current UI bug work, reproduce and verify changes in the normal Release
app with a live session. Capture the same screen before and after each fix.
Pause offline replay captures for this work; they do not establish that a
live-screen defect is fixed.

With the target window visible on the Snow Leopard desktop and SSH access
available through the `MacBook` alias, run:

```sh
./scripts/capture-ui-snow-leopard.sh --host MacBook
```

The script runs `screencapture` on Snow Leopard, copies the full-screen PNG
into the git-ignored `artifacts/snow-leopard/screenshots/` directory via SCP,
and removes its temporary remote file. Use `--output PATH` to name a capture
for a specific fixture and window size. This verifies actual 10.6 rendering;
the DevLocal view capture remains useful for deterministic local regression.

## Recorded results

### Mac OS X 10.6.8 / Xcode 4.2 — 2026-10-15

#### Discord look pass (scrollers, popouts, role colors, day dividers, composer)

- Built the normal Release target on the `MacBook` Snow Leopard machine with
  Xcode 4.2 (x86_64, deployment target 10.6, XIB compilation excluded, the 11
  existing compatible nibs kept). Remote source matched commit `e9abf06` before
  the changed files were copied; every copied file was checksum-verified.
- The previous Release app is kept as `build-production/Release-before-20261015`
  on the remote machine.
- Launched with the existing Keychain session (the user approved the Keychain
  prompt each time the unsigned binary changed). Navigation only: server and
  channel selection, member list, one member profile, emoji picker open/close.
  No message, reaction, typing notification or settings write was triggered.
- Verified: dark thin scroller thumbs in channel list, chat and member list;
  member-list selection drawn as a dark rounded row with readable names;
  borderless rounded profile card and emoji picker, both closed with Escape;
  role colors on chat author names (REST history once member data arrived) and
  member-list names; Japanese-locale day dividers; attach button inside the
  composer field and a `Message #channel` placeholder.
- Found and fixed on the device: channel-name emoji in the placeholder and
  emoji in profile role chips drew as missing-glyph boxes (now Twemoji); an
  Aqua focus ring appeared on the member list after closing a popout (focus
  rings disabled on member, search-result and thread tables). Re-verified after
  rebuilding.
- Final executable SHA256:
  `f57f9c669211f6cd959f0565ef63b88c1028efe7806ab4baf8c3e449dd29f2b6`.
- Screenshots: `artifacts/snow-leopard/20261015-ui/` (`rules.png`,
  `members.png`, `profile-popout.png`, `emoji-popout.png`, `fix-rules.png`,
  `fix-profile.png`, `fix-esc.png`).
- Not verified: Lion / Mountain Lion, sticker picker, thread and search panes
  on the device, other themes, write operations.

### Mac OS X 10.6.8 / Xcode 4.2 — 2026-10-01

#### User Profile follow-up — normal Release

- Reproduced the user-reported red close button failure on the expanded profile
  that was already open on the actual Snow Leopard desktop. The process was
  responsive. A runtime probe after clicking measured `isVisible=NO`, non-nil
  `parentWindow` and one remaining child window; no private content was printed.
- Added native `windowWillClose` parent detachment and explicit controller
  ownership of the panel across close operations.
- Verified own profile expansion/red close, reopening/Command-W, another
  member's expansion/red close and compact-card red close in normal Release.
  Screenshots: `profile-closed-fixed.png`, `profile-reopen-command-close.png`,
  `profile-final-closed.png`.
- Found and fixed dark custom-status text against a dark bubble, and wrapping
  metadata that clipped below its fixed row. Compared the same live member
  before and after in both compact and expanded profiles:
  `other-profile-card.png` / `other-profile-card-final.png`,
  `other-profile-expanded.png` / `other-profile-expanded-final.png`.
- Also verified opening and closing the normal emoji fallback panel with its
  native red button, without selecting an emoji: `profile-pass-picker.png`,
  `profile-pass-picker-closed.png`. No additional close failure was reproduced.
- Bio and connected-account information still render on multiple lines;
  metadata intentionally truncates to one line and retains its full tooltip.
- Xcode 4.2 Release build and source verification passed. No offline visual
  fixture was used. No private note editing/saving, message send, reaction,
  typing notification or account setting mutation was performed.
- Updated the local Release app and archive again. Remote and local final
  executable SHA256:
  `782b1325ed43674d65c2d49dc15abbed231df709b6a75f9af405a1c78d032d72`.
  Earlier hashes below describe the previous checkpoint only.
- Unsaved-note confirmation, write operations, other themes and Lion/Mountain
  Lion remain untested for this pass. This is not exhaustive all-screen QA.

#### Continued normal Release UI inspection

All visual checks below used the normal Release app at
`/Users/cocoro/Developer/legacy-discordClient-ui-debug/build-production/Release/Legacy Discord.app`
on the actual `MacBook` Snow Leopard machine, with its existing Keychain session.
No offline replay/test window was used for this inspection. Navigation was limited
to viewing servers/channels, resizing, scrolling and searching the local emoji
catalog. No message, reaction, composer typing notification or settings write
was intentionally triggered.

- Friends title, subtitle and first row remain visible at 960x640 and 747x524:
  `friends-final-wide.png`, `friends-final-narrow.png`.
- Native toolbar positions, themed member scroller, member/chat separation and
  all five existing reaction buttons remain inside their panes:
  `rules-final-wide.png`, `rules-final-narrow.png`.
- Narrow hover actions show the buttons that fit, Add Reaction and full Reply:
  `codex-release-hover-narrow.png`.
- Bundled Twemoji renders channel labels, reactions and picker images.
  The complete catalog can be scrolled to the final flag entries; typing `japan`
  filters the catalog: `codex-final-picker-tail.png`, `release-picker-search.png`.
- Snow Leopard's replacement search-cell default was measured as non-editable
  and non-selectable; the emoji, sticker and message search fields now set both
  flags explicitly. Live filtering was exercised in the emoji picker only.
- `sh scripts/check-twemoji-renderer.sh` passed on both current macOS and 10.6.8:
  3,781 catalog PNGs, Unicode round trip, variation selectors, skin tones, flags,
  keycaps, ZWJ, text attributes and cursor adjustment. This headless check does
  not replace production visual verification.
- Narrow message headers now omit dates that cannot fit, preserve the author,
  and restore full dates after widening: `message-header-final-narrow.png`,
  `message-header-final-wide.png` (final executable).
- `scripts/verify-source.sh` passed. Xcode 4.2 normal Release build succeeded.
- Copied the tested app back to local `build-production/Release/Legacy Discord.app`
  and updated `Legacy-Discord-10.6-Release.tar.gz` in the capture directory.
  Remote and local executable SHA256 both equal
  `edd524cf4524978e470a1b2e7c8c9f611863d8e986216886e959ccec2f696758`.
  Bundle contains 4,009 PNGs, catalog, both licenses and 11 compatible nibs.
  Replay fixture entry points are absent; diagnostics class remains compiled
  as disabled no-op methods in normal Release.

Screenshot names above are under `artifacts/snow-leopard/20261001-ui-debug/`.
Composer insertion/sending, reaction mutation, login/logout, and the full smoke
matrix were not exercised in this read-only pass. The current artifact has not
been tested on Lion or Mountain Lion. The bundled catalog is Unicode Emoji 16;
Twemoji assets are 17.0.3 with their graphics/Unicode licenses included.


- [x] Built the normal `Discord Lite` target in Release as x86_64 with a 10.6
  deployment target and without `LEGACY_DISCORD_LOCAL_DEV` or
  `LEGACY_DISCORD_UI_DIAGNOSTICS`.
- [x] Confirmed that offline replay entry points are absent from the Release
  executable and that the shared UI controller methods are present.
- [x] Added the 11 Snow Leopard-compatible compiled nibs from the previous
  checkpoint. Every XIB still present in the current source matches that
  checkpoint; Xcode 4.2 cannot compile the current XIB format directly.
- [x] Launched the normal Release app with its existing Keychain session and
  captured its Friends screen before and after the right-edge scrollbar fix.
  See `artifacts/snow-leopard/20261001-ui-debug/friends-production-before.png`
  and `friends-production-after-clean.png` in the same directory.
- [x] Opened the three visible servers in the normal Release app without
  sending messages or reactions. Captured each server before and after clearing
  the stale Friends/previous-channel header on server selection.
- [ ] Complete the normal login, messaging, and other-screen smoke tests. The
  earlier channel, picker, and profile captures used offline replay and do not
  prove those screens in a live session.

The following 10.8.5 results predate the deployment-target change to 10.6.
They remain useful regression history, but they do not validate the new binary
on Snow Leopard. The complete smoke test must be repeated on 10.6.8, 10.7.5,
and 10.8.5 before legacy support is declared complete.

### OS X 10.8.5 / Xcode 5.0.2 — 2026-08-19

- [x] Built successfully as an x86_64 application over SSH.
- [x] Launched and rendered the login window.
- [x] Signed in with the dedicated test account using email and password.
- [x] Displayed server information.
- [x] Displayed channel messages.
- [x] Confirm message send, edit, delete and reply.
- [x] Confirm live receipt of a message sent from another client.
- [ ] Confirm attachment upload.
- [x] Confirm reconnect after temporarily disabling Wi-Fi; server content resumes
  within several seconds after connectivity returns.
- [x] Confirm Keychain session restoration after quitting and reopening from Finder.
- [ ] Confirm Keychain deletion on logout.

### Native UI regression — 2026-08-19

- [x] Confirm the Aqua visual theme is applied on OS X 10.8.5.
- [x] Confirm saved-session restoration after the UI changes.
- [x] Confirm server and message loading after the UI changes.
- [x] Confirm message edit, delete and reply after the UI changes.
- [x] Confirm channel categories expand and collapse in the native source list.
- [x] Confirm mouse and Up/Down-arrow channel selection load the correct messages.
- [x] Confirm DM selection and live unread/mention labels in the native source list.
- [x] Confirm send, edit, delete and reply still work after the source-list migration.
- [x] Confirm server selection loads the correct channel list.
- [x] Confirm Up/Down-arrow server selection and scrolling.
- [x] Confirm server-name tooltips, unread markers and mention badges.
- [x] Confirm DM, channel and message operations after the native server-list migration.
- [x] Confirm server icons render upright after correcting flipped table coordinates.
- [x] Confirm the toolbar reports Connected, Reconnecting and Connected across a Wi-Fi interruption.
- [x] Confirm Reload refreshes the selected channel without changing its selection.
- [x] Confirm loaded-message text search advances on Return and highlights the result.
- [x] Confirm `@username` and `@username message` author-filter searches.
- [x] Confirm typing does not search or beep before Return is pressed.
- [x] Confirm an empty or unmatched search remains silent and does not disturb message state.
- [x] Confirm send, edit, delete and reply with the native toolbar present.

### Reaction UI

- [x] Confirm existing Unicode reactions and counts appear below a message.
- [ ] Right-click a message, open Reactions, and add one of the five standard reactions.
- [x] Confirm the reaction appears without reloading on this client and another client.
- [ ] Confirm a reaction added by the test account is checked and says Remove in the menu.
- [x] Remove a supported reaction and confirm both clients update without reloading.
- [x] Confirm a custom server emoji already attached to a message appears in the summary and menu.
- [ ] Confirm messages with replies and attachments remain correctly aligned after a reaction changes.
- [x] Confirm repeated reaction changes do not stall the UI or reload attachment previews.
- [x] Confirm reply author names and avatars remain visible after reaction changes.
- [x] Confirm Add/Remove changes immediately when reopening the reaction menu.

### Custom emoji

- [ ] Confirm a native icon button appears at the right side of the message composer.
- [ ] Confirm it opens a searchable popover with standard and custom emoji in an image grid.
- [ ] Select a custom emoji and confirm its image, rather than a `:name:` alias, appears at the caret.
- [ ] Send it and confirm the image appears inline on this client and another client.
- [ ] Confirm a custom-emoji reaction uses its image rather than a `:name:` placeholder.
- [ ] Revisit the channel and confirm cached emoji render without a visible pause.
- [ ] Confirm editing and saving a message containing a custom emoji preserves the emoji.
- [ ] Confirm the Direct Messages emoji menu reports that no server emoji are available.
- [ ] Hover a message and confirm its upper-right action bar appears and disappears cleanly.
- [ ] Confirm the action bar offers three recent reactions, Add Reaction and Reply.
- [ ] Confirm Add Reaction opens the same searchable image-grid popover.
- [ ] Confirm choosing a reaction updates the three recent-reaction buttons.

Keychain storage succeeds when the application is opened directly from Finder.
An application launched from an SSH bootstrap session receives
`errSecInteractionNotAllowed` (`OSStatus -25308`) on OS X 10.8, even though its
windows are visible. Authentication and session-persistence tests must therefore
launch the built application locally from Finder.

For a failure report, save the HTTP status, Gateway close code, event name and
OS version. Redact `Authorization`, `token`, `ticket`, CAPTCHA values and user
identifiers before sharing logs.
