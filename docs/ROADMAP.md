# Roadmap

## Milestone 0: maintainable Intel baseline

- [x] Import Discord Lite with attribution and GPL license
- [x] Set the deployment target to OS X 10.7 and architecture to x86_64
- [x] Move REST and Gateway version constants to v10
- [x] Store the session token in Keychain and migrate the old preference
- [x] Enable TLS certificate and hostname verification with a current CA bundle
- [x] Handle Gateway reconnect and invalid-session opcodes
- [x] Verify Gateway reconnect after a Wi-Fi interruption on 10.8.5
- [x] Build on Xcode 5.0.2 with the Mountain Lion SDK
- [x] Smoke-test login, Keychain session restoration, server sync and messaging on 10.8.5
- [ ] Smoke-test login, server sync and message display on 10.9.5
- [ ] Record current Gateway payload differences and fix initial sync

## Milestone 1: daily text client

- [x] Establish and regression-test the Mountain Lion-style Aqua theme and Legacy Discord branding
- [x] Replace and regression-test the channel and DM stacks with a native `NSOutlineView` source list
- [x] Replace the server icon stack with a native `NSTableView`
- [x] Add a native toolbar with Gateway state, channel reload and loaded-message search
- [x] Reaction payload model, live Gateway updates and add/remove REST actions
- [x] Reaction display and message context-menu actions
- [x] Custom emoji rendering and picker
- [ ] Unread and mention state that survives relaunch
- [ ] Member/profile inspector
- [ ] Link embed cards with a strict native renderer
- [ ] Image cache with bounded disk usage
- [ ] Connection state and reconnect indicator

## Milestone 2: modern channel features

- [ ] Thread navigation and thread message composer
- [ ] Forum channel post list
- [ ] Channel message search
- [ ] Pins and improved attachment handling
- [ ] Notification and per-channel mute controls

## Milestone 3: voice

- [ ] Voice Gateway session
- [ ] UDP discovery and encrypted transport
- [ ] Opus encode/decode through Core Audio
- [ ] Input/output device selection and mute/deafen

Video, Go Live and screen sharing are intentionally outside the first three
milestones.
