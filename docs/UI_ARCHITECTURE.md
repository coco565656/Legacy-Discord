# Legacy Discord UI Architecture

This document describes the implemented Phase 1C ownership boundaries. It is
not a future design. The main window remains XIB-backed, while feature
controllers own the state and behavior attached to those views.

The visual direction is the official Discord client's dark theme and layout,
built from AppKit views. Discord Messenger provides a feature reference only. Live UI defect work is validated through the normal
Release app on Snow Leopard with server and channel reading operations.

## Main Window

Owner: `DLMainWindowController`

Responsibilities: Compose feature controllers; install and coordinate the main
split view; route `DLController` callbacks; coordinate server, channel, DM and
screen transitions; propagate theme/scale notifications; open Settings and
perform logout.

State owned: Window-composition state, pane references, child-controller
references, the high-level loading guard, and the external main-window delegate.

Views owned: The XIB's root window and pane containers. Individual feature
views are handed to their dedicated controllers.

Delegates owned: `DLControllerDelegate`, `DLUserDelegate`, child-controller
coordination delegates, and `NSSplitViewDelegate`.

Communicates with: `DLController`, every feature controller listed below,
`DLPreferencesWindowController`, and its application delegate.

Must NOT own: Table/outline rows, message cells, composer state, picker state,
profile caches, search/thread/pin state, member rows, or detailed header state.

## Server Navigation

Owner: `DLServerNavigationController`

Responsibilities: Build and update server rows, synchronize selection, display
server images and unread state, and apply navigation theme styling.

State owned: Server item array, table view, selection-update guard.

Views owned: Server `NSTableView` and its programmatic row views.

Delegates owned: `NSTableViewDataSource`, `NSTableViewDelegate`, `DLServerDelegate`.

Communicates with: `DLMainWindowController` through
`DLServerNavigationControllerDelegate`.

Must NOT own: Channel loading, message loading, or global screen transitions.

## Channel Navigation

Owner: `DLChannelNavigationController`

Responsibilities: Build guild-channel and DM rows, category hierarchy and
selection; forward image changes; apply source-list theme styling.

State owned: Channel item array, outline view, selection-update guard.

Views owned: Channel/DM `NSOutlineView` and its programmatic row views.

Delegates owned: `NSOutlineViewDataSource`, `NSOutlineViewDelegate`, `DLChannelDelegate`.

Communicates with: `DLMainWindowController` and `DLDirectMessageController`.

Must NOT own: Conversation message rendering or server selection.

## Read State

Owner: `DLMessageReadStateController`

Responsibilities: Track whether the user is at the latest message, count pending
messages, acknowledge reads, and present history/unread/jump banners.

State owned: Pending count/date, first unread ID, banner controls.

Views owned: History banner, unread banner and jump/read buttons.

Delegates owned: Its private button actions and
`DLMessageReadStateControllerDelegate` callback contract.

Communicates with: `DLMessagePresentationController` and `ChatScrollView`.

Must NOT own: Message fetching or message-row rendering.

## Member List

Owner: `DLMemberListController`

Responsibilities: Request, group and present members; manage member-pane
visibility; load avatars and forward profile selection.

State owned: Member items, avatar request set, active server/channel, request
bounds/in-flight state, visibility.

Views owned: Member pane, title, scroll view and table rows.

Delegates owned: `NSTableViewDataSource`, `NSTableViewDelegate`, `DLUserDelegate`.

Communicates with: `DLController`, `DLMainWindowController`,
`DLUserProfileController`.

Must NOT own: Profile popovers or global channel transitions.

## Profile

Owner: `DLUserProfileController`

Responsibilities: Present compact and detailed profiles; request and cache
profile, avatar and banner data; render roles, status and metadata.

State owned: Selected profile models, panels/popover, request sets and caches.

Views owned: Profile popover, detail panel and their content views.

Delegates owned: `AsyncHTTPRequestDelegate` for profile assets/data.

Communicates with: `DLController`, `DLMemberListController`,
`DLMainWindowController`.

Must NOT own: Member table population or message rendering.

## Threads

Owner: `DLThreadController`

Responsibilities: Present thread list/detail panes, request refreshes and route
thread/base-channel selections.

State owned: Thread items, base channel, list/detail visibility.

Views owned: Thread list pane, table, empty state and detail pane.

Delegates owned: `NSTableViewDataSource`, `NSTableViewDelegate`.

Communicates with: `DLController` and `DLMainWindowController` through
`DLThreadControllerDelegate`.

Must NOT own: Base channel message orchestration.

## Search

Owner: `DLMessageSearchController`

Responsibilities: Manage search input, result pages, author resolution,
highlighting, result navigation, and the shared pinned-message result display.

State owned: Query/results, offsets, total, highlighted result and pane state.

Views owned: Search field integration and results pane/table/controls.

Delegates owned: `NSTableViewDataSource`, `NSTableViewDelegate`.

Communicates with: `DLController`, `DLMainWindowController`, `DLPinsController`,
and `ChatScrollView`.

Must NOT own: Normal message loading or message-cell layout.

## Pins

Owner: `DLPinsController`

Responsibilities: Coordinate pin-button state, pinned-message requests and
presentation through the Search result pane.

State owned: Active state and button/search-controller references.

Views owned: Pin button state; result rows remain owned by Search.

Delegates owned: `DLPinsControllerDelegate` permission callback.

Communicates with: `DLController`, `DLMessageSearchController`,
`DLMainWindowController`.

Must NOT own: An independent message renderer.

## Emoji

Owner: `DLEmojiPickerController`

Responsibilities: Build/search the standard/custom emoji picker, load emoji
assets, present it with the compatibility popover, and report selections.

State owned: Picker items, search/scroll views, popover and reaction target.

Views owned: Programmatic emoji picker content.

Delegates owned: `AsyncHTTPRequestDelegate` and picker control actions.

Communicates with: `DLMessageComposerController` through
`DLEmojiPickerControllerDelegate`.

Must NOT own: Composer text state, message sending, or Unicode message rendering.

## Stickers

Owner: `DLStickerPickerController`

Responsibilities: Build/search/present sticker choices, load sticker assets and
report selections.

State owned: Sticker items, search/scroll views and compatibility popover.

Views owned: Programmatic sticker picker content.

Delegates owned: `AsyncHTTPRequestDelegate` and picker control actions.

Communicates with: `DLMessageComposerController` through
`DLStickerPickerControllerDelegate`.

Must NOT own: Message transport or conversation rendering.

## Composer

Owner: `DLMessageComposerController`

Responsibilities: Text editing and dynamic height; reply and attachment state;
mention/channel candidates; emoji/sticker insertion; typing state; prepare send
intent and hand it to the application coordinator.

State owned: Editor, pending attachments, reply, candidate state, typing users
and timer, input geometry, picker controllers.

Views owned: Existing XIB composer views, candidate list, pending-attachment
content and picker interactions.

Delegates owned: `NSTextViewDelegate`, `ChatScrollViewDelegate`, attachment,
candidate, editor, emoji, sticker and typing delegates.

Communicates with: `DLMainWindowController` via
`DLMessageComposerControllerDelegate`, plus `DLController` only through those
coordinator requests.

Must NOT own: REST/Gateway implementation, message history, or message cells.

## Friends / Direct Messages

Owner: `DLDirectMessageController`

Responsibilities: Present Friends/Home, coordinate the DM source list/header,
DM selection and narrow-window channel-pane behavior.

State owned: Friends channels, home view, compact-layout state and restored pane width.

Views owned: Friends/Home view and its scroll content; DM header presentation;
DM source rows are owned by `DLChannelNavigationController`.

Delegates owned: Its home/DM actions and `DLDirectMessageControllerDelegate`.

Communicates with: `DLMainWindowController`, `DLChannelNavigationController`,
`ChatScrollView`.

Must NOT own: A DM-specific message renderer or network transport.

## Message Rendering

Owner: `DLMessagePresentationController` for orchestration;
`DLMessage` -> `ChatItemViewController` -> `ChatScrollView` for the shared renderer.

Responsibilities: Load initial/older/newer/around-result messages; route live
updates; preserve read/search/pin/composer integration; create and update shared
message rows for guild, DM and replay data.

State owned: First/last message, loading flags, search-history window state,
pending deletion, DevLocal replay guard.

Views owned: `ChatScrollView` content through shared `ChatItemViewController` rows.

Delegates owned: `ChatItemViewControllerDelegate` and
`DLMessageReadStateControllerDelegate`.

Communicates with: `DLController`, Read State, Search, Pins, Channel Navigation,
Composer, Profile and `DLMainWindowController`.

Must NOT own: Composer editing, a fixture-only renderer, or source-list rows.

## Header / Connection UI

Owner: `DLMainHeaderController`

Responsibilities: Configure toolbar controls; present connection state; enable
reload/member actions; coordinate Search and Pins controls; apply header theme.

State owned: Header controls and current connection state.

Views owned: Programmatic header controls attached to the XIB header containers.

Delegates owned: Header button actions.

Communicates with: `DLMainWindowController`, `DLMessageSearchController`,
`DLPinsController`.

Must NOT own: Message fetching, member rows or connection transport.

## Settings

Owner: `DLPreferencesWindowController` for presentation and
`DLPreferencesHandler` for persistent local values.

Responsibilities: Present available settings, validate/apply changes, persist
proxy/display-scale/theme values and publish change notifications.

State owned: Settings controls and local defaults.

Views owned: Preferences window, programmatic sidebar/panes and XIB proxy controls.

Delegates owned: Preferences control actions.

Communicates with: `DLMainWindowController` and all notification observers.

Must NOT own: Discord-side `DLUserSettings` data or feature rendering logic.

## Theme

Owner: `DLPreferencesHandler` for selected theme; `DLUtil` for shared palette
colors; each feature controller applies that palette to views it owns.

Responsibilities: Persist theme selection, publish
`DLAppearanceThemeDidChangeNotification`, provide shared colors, redraw owned views.

State owned: Selected theme value in local defaults.

Views owned: None centrally; feature owners style their own views.

Delegates owned: Notification observers in the composition/controller layer.

Communicates with: `DLMainWindowController`, `DLUtil`, and feature controllers.

Must NOT own: Per-screen hard-coded theme branches or message/network state.

## Fixture boundary

DevLocal fixtures and sanitized replay change only the data and deterministic
state supplied to these production controllers. They use the same views,
controllers, cell creation, layout, row-height, image, Markdown, theme and
display-scale paths as live mode. Fixture code must never become a parallel UI.
