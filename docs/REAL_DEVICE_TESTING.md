# Real-device testing

Use only the dedicated test account while protocol compatibility is being
developed. Do not copy its token into source files or issue reports.

## Primary matrix

| Machine | OS | Priority |
| --- | --- | --- |
| MacBook Pro 13-inch Mid 2012 | OS X 10.8.5 | Primary |
| MacBook Pro 15-inch Retina Mid 2012 | OS X 10.9.5 | Primary |
| 64-bit Intel test machine or VM | Mac OS X 10.7.5 | Secondary |

## First smoke test

1. Create a private test server with two text channels and the test account.
2. Launch the client and sign in through the normal login form.
3. Confirm that the token appears in Keychain Access under
   `org.legacydiscord.client` and does not appear in Console logs.
4. Relaunch and confirm that the session resumes without another login.
5. Verify server and DM initial sync, message send/receive, reply, edit, delete,
   image upload, typing state and reconnect after Wi-Fi is toggled.
6. Log out and confirm the Keychain item is deleted.

## Recorded results

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
