# Roadmap

## Milestone 0: maintainable Intel baseline

- [x] Import Discord Lite with attribution and GPL license
- [x] Set the deployment target to Mac OS X 10.6 and architecture to x86_64
- [x] Replace Lion-only popover and Keychain entry points with Snow Leopard-compatible paths
- [x] Move REST and Gateway version constants to v10
- [x] Store the session token in Keychain and migrate the old preference
- [x] Enable TLS certificate and hostname verification with a current CA bundle
- [x] Handle Gateway reconnect and invalid-session opcodes
- [x] Verify Gateway reconnect after a Wi-Fi interruption on 10.8.5
- [x] Build on Xcode 5.0.2 with the Mountain Lion SDK
- [x] Smoke-test login, Keychain session restoration, server sync and messaging on 10.8.5
- [x] Build and smoke-test the 10.6-targeted binary on Mac OS X 10.6.8 (Xcode 4.2, signed; daily use since 2026-10)
- [ ] Smoke-test the same binary on Mac OS X 10.7.5 and OS X 10.8.5 (10.8.5 will be re-checked when the Mountain Lion Mac is set up for voice)
- [ ] Best-effort smoke-test login, server sync and message display on OS X 10.9.5
- [x] Record current Gateway payload differences and fix initial sync (READY without merged_members, user_guild_settings entries, read state; see REAL_DEVICE_TESTING)

## Milestone 1: daily text client

- [x] Establish and regression-test the Mountain Lion-style Aqua theme and Legacy Discord branding
- [x] Replace and regression-test the channel and DM stacks with a native `NSOutlineView` source list
- [x] Replace the server icon stack with a native `NSTableView`
- [x] Add a native toolbar with Gateway state, channel reload and loaded-message search
- [x] Reaction payload model, live Gateway updates and add/remove REST actions
- [x] Reaction display and message context-menu actions
- [x] Custom emoji rendering and picker
- [x] Private user notes in the expanded profile, adapted from Discord Messenger
- [x] Confirmation before opening links in message text
- [x] Unread and mention state that survives relaunch (Discord read state from READY; verified on 10.6.8)
- [x] Member/profile inspector (official popout, Message @user, full profile window)
- [x] Link embed cards with a strict native renderer (official card style, accent colour, PNG media)
- [x] Image cache with bounded disk usage (32 MB memory + 200 MB disk LRU, Clear Cache in Settings)
- [x] Connection state and reconnect indicator (header status dot, stall watchdog, reconnect on unexpected close)

## Milestone 2: modern channel features

- [x] Thread navigation and thread message composer (Threads list, full-width threads with breadcrumb)
- [x] Forum channel post list (official cards, search, New Post draft)
- [x] Channel message search (official result cards, highlights, paging)
- [x] Pins and improved attachment handling (pin cards, payload_json uploads, 10 MB limit, spoilers; sending an attachment still to be confirmed on a device)
- [x] Notification and per-channel mute controls (server/channel/category/DM mute with durations, Dock badge and bounce; badge verified on 10.6.8)

## Milestone 3: voice

- [ ] Voice Gateway session
- [ ] UDP discovery and encrypted transport
- [ ] Opus encode/decode through Core Audio
- [ ] Input/output device selection and mute/deafen

Video, Go Live and screen sharing are intentionally outside the first three
milestones.
