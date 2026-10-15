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

## Snow Leopard builds and signing

`scripts/remote-build-snow-leopard.sh --run` syncs the tracked sources to the
`MacBook` host, builds Release with Xcode 4.2, signs the app with the
self-signed "Legacy Discord Dev" identity and relaunches it.

The token is stored in the Keychain, which remembers "Always Allow" per code
signature. Unsigned builds changed signature on every rebuild, so the Keychain
asked each time. Run `--setup-signing` once per test Mac: it creates the
identity in a dedicated `~/Library/LegacyDiscordSigning/signing.keychain`
(random password in a file only that user can read; the login keychain is not
touched). After that, choose "Always Allow" once for the signed app.

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

#### User profile popout

- Official layout: banner, 80 pt avatar with a ring and presence dot, custom
  status bubble, name, "username \u2022 pronouns" (Twemoji), and an inner
  panel with ABOUT ME (wrapping, hidden without a bio), MEMBER SINCE (Discord
  account date from the ID, server join date) and all ROLES (the card grows
  with them). Others' profiles end with a "Message @name" field: Return opens
  the DM (created with `POST /users/@me/channels` if needed) and leaves the
  text in the composer as a draft.
- Side popouts line up with the clicked row and stay inside the window.
  Clicking an already selected member opens the profile again.
- Verified on 10.6.8 with three profiles, including Message @256 opening the
  existing DM with the draft. During that test an extra Return sent by the
  test script also sent the draft; it was deleted about a minute later.

#### Search, pins and embeds

- Search results and pinned messages use official-style cards: avatar,
  role-coloured name, "Today at" style time, up to three lines of text with
  the search words highlighted, hover state and click to jump. The header
  reads "N Results" with the channel below; Back/Next are dark buttons and
  only appear when there is more than one page. Official empty states.
- Fixed: Cmd-V pasted into the message composer even while the search field
  (or any other field) had focus, because the composer handled the shortcut
  for the whole window.
- Embed cards: dark rounded card with the embed colour as a left bar,
  provider/author, title and a measured description (CJK text no longer
  clipped); the top line was clipped by NSBox's default margins. Embed images
  from Discord's proxies request PNG, as they could arrive as WebP.
- Verified on 10.6.8: a "codex" search (9 results, highlighted), pins in an
  empty channel and in a channel with one pin, and an x.com embed whose image
  was previously blank.

#### Attachments

- Uploads use Discord's documented multipart form: a `payload_json` part with
  the full message (so replies and stickers keep their reference) and
  `files[n]` parts. The old form named each part after its file, dropped
  everything but `content`, and two files with the same name collided.
- Files over 10 MB are refused with the official "Your files are too
  powerful" message; at most 10 attachments per message. Pasted images are
  named `image.png`.
- Pending attachments have a menu with Mark as Spoiler / Remove Spoiler (the
  `SPOILER_` prefix) and Remove Attachment. Received spoiler images are shown
  blurred with a "SPOILER" pill until clicked.
- Verified on 10.6.8: pasting an image adds it to the tray, Mark as Spoiler
  dims it and labels it, an 11 MB file shows the alert, and removing the item
  clears the tray. Actually sending an attachment and viewing a received
  spoiler image were not exercised yet.

#### Image disk cache

- Avatars, emoji, stickers, banners and attachment previews are cached in
  `~/Library/Caches/<bundle id>/Images`: a 32 MB in-memory LRU in front of a
  200 MB disk cache trimmed (oldest first, down to 150 MB) at launch and every
  200 writes. Signed CDN parameters (`ex`, `is`, `hm`) are dropped from the
  cache key so the same image is reused across sessions. Settings > Advanced
  shows the usage and has Clear Cache.
- Verified on 10.6.8: files appear in the cache directory; after a relaunch a
  server's avatars, image preview and reaction emoji were all visible within
  two seconds of opening it.

#### New forum posts

- Forum lists have the official blurple "New Post" button. It opens a draft
  card with a title, a message (Option-Return for new lines), the forum's tags
  as toggle pills, Cancel and Post. Post sends
  `POST /channels/{forum}/threads` with `applied_tags`; forums flagged
  REQUIRE_TAG need a tag. The new post opens right away and is shown as joined.
- Verified on 10.6.8: the draft opens, an empty Post shows "A post needs a
  title and a message." without sending, tags toggle, Cancel restores the
  list.
- End-to-end on the user's own server (with permission): created
  "Legacy Discord test post", which appeared in the list and under the forum
  in the sidebar; opened it and sent a reply, which appeared in the post; then
  deleted it with the new Delete Post item (confirmation sheet). After a
  relaunch the post was gone everywhere.
- Fixed during the run: requests answered with 201 Created (post creation)
  were treated as failures, so the draft reported an error although the post
  existed; any 2xx is now a success. The sidebar now refreshes on thread
  create/delete events, and a post's message count goes up as replies arrive.
- Post card menu: Open Post, Copy Link, and Delete Post for one's own posts or
  on servers the user owns.

#### Forum post list, thread list and WebP previews

- Forum and media channels show the official post list: a "Search posts"
  field and cards with applied tags, title, the opening message as
  "author: text" (fetched lazily with `messages?around={post}&limit=1`, since
  `GET /messages/{id}` is bot-only), message count and last activity. Posts
  open full-width with a "forum › post" header and thread icon.
- Text channels and threads gained the official Threads header button, which
  shows the same list with a title, search and close button.
- Forum channels use the speech-bubble icon in the sidebar and header.
- The header no longer reverts to the bare channel name when messages load,
  so channel topics and thread breadcrumbs stay visible.
- Image previews were blank for many recent uploads: the media proxy answered
  resized requests with WebP, which 10.6 cannot decode. Previews now request
  `format=png` (or `jpeg` for photos).
- Verified on 10.6.8 in a test server: forum cards with tags and opening
  messages, opening a post, the Threads button and its empty state/close,
  topic in the header, and previously blank screenshots now visible.

#### Forwarded messages and signed builds

- Forwarded messages (`message_snapshots`) now show a muted "↪ Forwarded"
  line followed by the original text, attachments, embeds and stickers. They
  never ping, are never shown as jumbo emoji, and offer no Edit item.
- Verified on 10.6.8: the forwarded message from 13:44 in a test server,
  previously an empty row, shows the label, the explanation text and the
  full code block.
- The first signed rebuild after choosing "Always Allow" launched and logged
  in without any Keychain prompt.

#### Clipped message text and avatars

- Row heights were measured before the message text had been laid out at the
  row's real width (the text view still reported the nib's one-line height or
  width), so wrapped messages were clipped by the next row. Rows now get their
  width first, and the text is laid out and sized before measuring.
- Messages without text (here an apparently forwarded message with empty
  content) were only as tall as the header spacing, cutting off the avatar;
  non-compact rows now always leave room for the avatar.
- Verified on 10.6.8 in the two channels where it was seen. Forwarded message
  content (`message_snapshots`) is not rendered yet.

#### Crashes when sending emoji

- Crash 1 (`-[NSControl _setWindow:]` from `populateMessageActionBar:` in
  `cachedEmojiDidUpdate:`): every message using a newly downloaded custom
  emoji rebuilt its own hover bar, which never joins a window; removing its
  tooltip buttons crashed. That bar is now only rebuilt while on screen, and
  the shared hover bar updates emoji images in place instead of recreating
  buttons.
- Crash 2 (`release` inside `-[AsyncHTTPPostRequest dealloc]`): the message
  nonce from `+[DLUtil generateSnowflake]` was autoreleased twice, so any sent
  message could crash once the request was freed. Fixed; the clang static
  analyzer reports no other new over-releases (remaining reports are the
  original `[self.view release]` pattern and a `finalizedMessage` naming false
  positive; its `mutableCopy` leak was fixed).
- Custom emoji whose name contains digits (`<:20240614_214205:ID>`) took the
  first digits of the name as the ID, failed to load and showed `:name:` at
  jumbo size across several lines. The ID is now the digits after the last
  colon, and the not-yet-loaded fallback is drawn at text size.
- Verified on 10.6.8: the user sent custom emoji and received a DM with a
  custom emoji after the fixes without a crash; the `20240614_214205` emoji
  now renders as an image.

#### Notifications and mute

- READY `user_guild_settings` (and `USER_GUILD_SETTINGS_UPDATE`) are kept per
  server. Muted channels/categories are dimmed; any mute (channel, category or
  server) hides the unread pill and bold name, while mention badges remain.
  Mentions honour role mentions and `suppress_everyone`; muted conversations
  make no sound or bounce.
- Channel, category, DM and server menus gained Mute (15 minutes, 1/3/8/24
  hours, until turned back on) and Unmute, sent as
  `PATCH /users/@me/guilds/{id}/settings` like the official client.
- Settings > Notifications: Enable Unread Message Badge (Dock badge with the
  mention + DM count) and Bounce Dock Icon (informational request while the app
  is in the background), next to the existing mention sound.
- Verified on 10.6.8 (with the user's permission to write the setting): muted
  a channel for 15 minutes from the context menu, the channel dimmed, the mute
  was still present after relaunch (so Discord stored it), then Unmute Channel
  restored it. Server menu shows the Mute Server submenu (not exercised). The
  Notifications pane shows the three toggles.
- Fixed during the pass: a channel without a category has an `NSNull` parent
  ID; calling `length` on it raised in drawing and left the window half
  rendered.
- Dock badge verified on 10.6.8: with the app in the background, a DM from
  another account showed "1" on the Dock icon (and on the home icon and DM
  row); opening the DM cleared all three. A DM arriving while that DM was open
  correctly added no badge. The bounce itself was not captured in a
  screenshot. The duplicated server-menu separator was removed.

#### Remaining checks and fixes

- Verified on 10.6.8: window resize and zoom with the dark title bar; dark
  Settings title bar; Settings minimize and restore from the Dock;
  member-list row hover; Friends Online/All/Pending/Blocked tabs; opening a DM
  from a friend row; channel Copy Link (clipboard checked with `pbpaste`);
  Mark As Read on an unread channel (pill and bold title cleared); the
  older-messages bar with Jump To Present on a long channel.
- Fixed: author names and timestamps in a DM opened from the Friends page were
  clipped ("co…", "2025/06/23 16:"). The header fields kept the nib's
  flexible-width autoresizing, so a transient narrow row shrank them for good;
  they are now sized only by `layoutMessageHeaderFields`. Confirmed fixed.
- Fixed: the older-messages bar was drawn at the top of the (flipped) chat
  scroll view; it now sits at the bottom above the composer, and the
  new-messages bar along the top edge. Confirmed for the older-messages bar.
- Fixed: the Friends page hid nothing in the header and left a DM row
  selected; search, pins and the member toggle are now hidden there and the
  DM selection is cleared. Member-list tooltips appear only for cut-off names.
- Not exercised: the new-messages bar (needs an incoming message while
  scrolled up), spoiler reveal (no spoiler in reachable history), the login
  window title bar (requires logging out).

#### Dark title bar

- `DLDarkTitlebarView` paints a dark title bar (rail color, rounded top
  corners, centered title dimmed when inactive) over the standard titled
  window's title area, below the traffic-light buttons, and ignores the mouse
  so the native frame keeps dragging, double-click and resizing. Installed on
  the main, Settings and login windows.
- Verified on 10.6.8: dark bar with traffic lights and title on the main
  window; dragging the bar moved the window (then moved back). Settings and
  login title bars, minimize/zoom and resizing were not exercised.

#### Message timestamps and login screen

- Message headers use the official format: "Today at 22:54", "Yesterday at
  22:54", otherwise the locale's short date with a four-digit year plus the
  short time. On 10.6 the short style is "yy/MM/dd" and date templates return
  年月日 forms, so only the year field is widened. Verified on 10.6.8
  (Japanese): "2022/05/04 0:55".
- Login window rebuilt like the official one (blurple backdrop, "Welcome
  back!", labelled borderless inputs, full-width blurple Log In button, token
  login as a link). Verified with the new `login-screen` DevLocal capture; not
  shown on the device because that requires logging out.

#### Hover states and sectioned emoji picker

- `DLContextTableView` tracks the hovered row: server icons grow a 20pt edge
  pill and become rounded squares on hover; member rows get the hover
  background.
- Emoji picker: left category column (server icon, then People, Nature,
  Food, Travel, Activities, Objects, Symbols, Flags; boundaries follow the
  catalog's Unicode order), section headers in the grid, borderless emoji
  cells. Search shows one unsectioned list.
- Fixed: the picker read `[DLController sharedInstance]`, which made offline
  replay read the Keychain and stall the emoji-picker fixture.
- Verified on 10.6.8: hover pill on a server icon, category column with the
  server icon, server-name header, and jumping to the FOOD section. Member
  row hover was not exercised.

#### Friends page and Gateway stall recovery

- READY `relationships` and friends' `presences` are now stored (plus live
  PRESENCE_UPDATE without guild_id). The DM home is the official Friends page:
  Online / All / Pending / Blocked tabs, "TAB — N" header, rows with avatar,
  presence dot, name and status or request type; clicking opens the existing
  one-to-one DM. Recent conversations remain the fallback without
  relationships.
- Verified on 10.6.8: Online (2, idle/dnd dots) and All (4, offline shown).
  Pending/Blocked tabs and opening a DM from a row were not exercised.
- Found on the device: one launch connected but never received Hello and
  stayed "Connecting" indefinitely (no heartbeat was ever scheduled). The
  Gateway thread now drops a connection that sends nothing for 20 seconds and
  any unexpected close triggers a reconnect. After the fix the app connected
  normally; the stall itself could not be reproduced on demand.

#### Context menus for servers, channels and members

- Added right-click menus in the official order, limited to working actions:
  server (Mark As Read, Copy Server Link), channel/DM (Mark As Read, Copy
  Link), category (Mark As Read, Collapse/Expand Category, Collapse All
  Categories), member (Profile, Mention, Copy Username); Developer Mode adds
  the matching Copy ID item. Mark As Read acknowledges the newest known
  message per channel and clears unread/mention state.
- Tables show their menu without AppKit's blue clicked-row outline
  (`DLContextTableView`, `DLChannelOutlineView menuForEvent:`).
- The hover toolbar's "Reply" text button is now a reply arrow icon.
- Verified on 10.6.8: server, channel and member menus; no blue outline;
  Mention inserted an `@256` mention into the composer, which was then
  cleared (no message sent; the composer's typing notification may have
  been sent briefly). Mark As Read was not exercised.

#### Server rail and settings dropdowns

- Server rail: selected pill (40pt) and unread dot (8pt) now hang off the
  rail's left edge instead of overlapping the icon; the mention badge sits at
  the icon's bottom-right inside a rail-colored ring.
- Settings: chat font and zoom pop-ups use a dark Discord-style dropdown cell
  (`DLDarkPopUpButtonCell`); the opened menu stays native.
- Verified on 10.6.8: rail pills at the edge and dark dropdowns in Appearance.
  The mention badge was not visible on the device (no mentions at the time).

#### Removing Discord Lite styling from the channel list and header

- Header: the reload button is hidden (the official client has none), the
  connection dot is shown only while not connected, and the channel topic is
  shown after the name ("name │ topic", full text in the tooltip).
- Channel list: AppKit disclosure triangles replaced by Discord's chevron;
  clicking a category toggles it (handled in mouseDown because Snow Leopard
  asks shouldSelectItem: more than once per click, which toggled twice);
  channels align with their category (threads stay indented); rows keep
  8-point side margins; the unread pill sits on the list's left edge.
- Verified on 10.6.8: chevrons, flush channels, margins, edge unread pills,
  hidden reload and connection dot, and collapse/expand of a category by click.
  The topic display was not verified (the opened channel has no topic).

#### User-reported UI fixes and channel visibility

- Author names no longer truncate in a wide chat (width measured with the
  text field cell, re-laid out when the name changes).
- Message context menu: read-only message text now shows only the Discord
  items (Add Reaction, Reply, Copy Text, Copy Message Link; Edit/Delete for own
  messages; Copy IDs with Developer Mode) instead of AppKit's Spotlight, Font,
  Spelling and Speech items. The gear opens Settings directly.
- New-messages / older-messages banners rebuilt like the official client
  (blurple top bar with Mark As Read, dark bottom bar with Jump To Present).
  Not verified on the device: needs a new incoming message or a long history.
- Found on the device: opening a server auto-selected a channel the account
  cannot view ("Missing Access"), and such channels were listed at all.
  Channel visibility is now computed from base role permissions and
  @everyone/role/member overwrites using the account's roles, fetched from
  `/users/@me/guilds/{id}/member` because READY lacked `merged_members`.
  Verified: ticket/admin channels disappear and the first visible text channel
  opens without an error.
- Offline replay no longer creates DLController (it read the Keychain and
  stalled a regression fixture).

#### Gateway thread-safety crash fix

- Crash reports from 2026-10-02 (heap corruption in NSMutableData realloc),
  2026-10-05 (SSL_write) and 2026-10-15 (bad pointer while rebuilding the hover
  action bar) are consistent with the Gateway libcurl handle being used from
  two threads: `curl_ws_send` / `curl_easy_setopt` on the main thread while
  `curl_easy_perform` ran on the WebSocket thread, and overlapping reconnect
  threads sharing one static receive buffer.
- Fix: one connect-only (`CURLOPT_CONNECT_ONLY = 2`) connection per thread run;
  that thread alone connects, receives, sends queued frames and cleans up.
  Other threads only enqueue frames. Connections are serialized with a lock
  and ended through a generation counter instead of cross-thread `setopt`.
- Also kept the quick-reaction button alive until its click finishes, since
  the action bar it belongs to is rebuilt from its own action.
- Verified on 10.6.8: connected (green) after launch and still connected after
  more than three minutes (several heartbeat intervals), DM list and messages
  loaded, no "Websocket Closed" log and no new crash report for the new
  process. Longer soak testing and reconnect after a network drop are not yet
  verified.

#### Markdown extensions and grouped member list

- Same remote build procedure; read-only navigation only.
- Verified: a real `<#channel>` mention in the rules channel now renders as a
  `#🐣 | 自己紹介` mention pill with Twemoji instead of the raw token.
- Verified: the member list groups online members under hoisted roles
  (e.g. `副管理者 — 4`, `🔈 | READING ALOUD BOT — 4`), shows online / idle /
  do-not-disturb dots and custom status text, and dims offline members.
- Group counts reflect loaded members (the client requests up to 500), so
  large servers can show smaller counts than the official client.
- Not verified on the device: role mentions, timestamps, headings, lists,
  masked links and spoiler reveal (no such messages were on screen); these are
  covered by the `channel-markdown` replay fixture.
- Final executable SHA256: `6f9bf6fcca422c41828ef5778235d5d1b08ff8c5616abc70f2a6029dd7e71d1e`.
- Screenshots: `md-rules-up2.png`, `members-grouped.png`.

#### User panel, Discord sizing and expanded settings

- Same remote build procedure as below; the new `DLUserPanelController` was
  added to the project and compiled by Xcode 4.2 without changes.
- Verified: 240-point channel sidebar (the split autosave name changed so
  existing installs start at 240 once), 32-point channel rows, user panel with
  darker background, green presence dot and disabled microphone/headphone
  buttons beside the settings gear.
- Opened Settings from the gear menu: web-style USER SETTINGS / APP SETTINGS
  sidebar, Appearance (theme swatches, chat font scaling, zoom level), My
  Account (real avatar, display name and username, read-only), Chat toggles.
- Turned "Show emoji reactions on messages" off: the open channel re-rendered
  without reaction bars and without layout gaps; turned it back on and the
  reactions returned. The preference was left at its original value (on).
- Final executable SHA256: `d140d32c3de22b0b3b7609f39ed3c0a6377ea4b6983076c9e4fbba9022e79db5`.
- Screenshots: `panel-server.png`, `settings-open.png`, `settings-account.png`,
  `settings-chat.png`, `reactions-off.png`, `reactions-restored.png`.
- Not verified on the device: chat font sizes other than the default, role
  color / animated emoji / embed / mention sound / Developer Mode toggles,
  Log Out from Settings.

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
