# Phase 1C Main Controller Audit

This audit records the implemented state at the end of the Phase 1C ownership
extractions. Counts are source counts, not metrics manufactured by moving code
into categories.

## Metrics

- `DLMainWindowController.m` before Phase 1C: 4,363 lines
- `DLMainWindowController.m` current: 779 lines
- implementation methods before Phase 1C: 166
- implementation methods current: 65
- header ivars before Phase 1C: 145
- current header ivars: 44
- protocol conformances before Phase 1C: 19
- current protocol conformances: 13
- nested/helper class implementations in the `.m`: 0

The `.m` contains one private class extension for declarations and one
file-local compatibility function,
`DLSetSplitHoldingPriorityIfSupported`. The function is narrow main-window
split-layout compatibility code, not a feature owner.

## Remaining method audit

All remaining implementation methods are classified as **MAIN WINDOW
COORDINATION**. No substantial **FEATURE-SPECIFIC** implementation remains.

Diagnostics and deterministic launch coordination:

- `writeSanitizedUIDiagnostics`
- `showLocalReplayFixtureNamed:windowSize:`
- `captureLocalReplayPNGToPath:`

Window composition, lifecycle, root layout and global presentation:

- `windowDidLoad`
- `moveView:toPane:frame:autoresizingMask:`
- `installResizableMainSplitView`
- `mainWindowDidResize:`
- `splitView:constrainMinCoordinate:ofSubviewAt:`
- `splitView:constrainMaxCoordinate:ofSubviewAt:`
- `splitViewDidResizeSubviews:`
- `messageDisplayScaleDidChange:`
- `appearanceThemeDidChange:`
- `applyCurrentTheme`
- `connectionStateDidChange:`
- `setDelegate:`
- `dealloc`

Cross-feature visibility and intent routing:

- `mainHeaderControllerDidRequestMemberListToggle:`
- `showThreadList:`
- `hideThreadBrowser`
- `threadController:selectChannel:`
- `threadController:restoreBaseChannel:`
- `messageSearchControllerWillShow:`
- `messageSearchControllerDidClose:`
- `pinsControllerMayOpen:`
- `messageComposerController:sendPreparedMessage:toChannel:`
- `messageComposerController:informTypingInChannel:`
- `messageComposerController:queryServer:forMembersContainingUsername:`
- `mainHeaderControllerDidRequestReload:`
- `showFileOpenDialog:`
- `showSettingsMenu:`
- `openUserSettings:`
- `removeReferencedMessage:`
- `logOutUser`

Server/channel/DM transition coordination:

- `serverNavigationController:didSelectServer:`
- `serverNavigationControllerDidFinishDisplayingItems:`
- `channelNavigationController:didSelectChannel:`
- `channelNavigationController:didFinishDisplayingItems:showingDirectMessages:selectedChannel:`
- `channelNavigationController:imageDidUpdateWithData:forChannel:`
- `directMessageController:didSelectChannel:`
- `selectServer:`
- `selectChannel:`
- `loadMainContent`
- `populateUserServers`
- `loadChannelsForServer:`
- `refreshThreadOutlineForServer:`
- `threadsDidUpdateForServer:`
- `archivedThreadsDidUpdateForServer:channel:`
- `loadDirectMessageChannels`

Member/profile coordination:

- `memberListController:didSelectUser:relativeToRect:ofView:`
- `memberListController:avatarDidUpdateForUser:`
- `user:avatarDidUpdateWithData:`
- `members:didUpdateForServer:`
- `userProfile:didLoadForUser:inServer:`

Application callback routing:

- `initialDataWasReceived`
- `requestDidFailWithError:`
- `channelPins:didLoadForChannel:`
- `messageSearchResults:totalResults:offset:forChannel:query:`
- `messages:receivedAroundSearchResult:forChannel:`
- `messages:receivedForChannel:`
- `newerMessages:receivedForChannel:`
- `newMessage:receivedForChannel:inServer:`
- `messagePresentationControllerNeedsDirectMessageRefresh:`
- `didLogoutSuccessfully`
- `userDidStartTypingInSelectedChannel:`
- `userDidStopTyping:`

## Remaining ivar audit

All 44 ivars are classified as **MAIN WINDOW COORDINATION** because they are
composition state, XIB outlets handed to feature owners, child-controller
references, or the external delegate.

Composition state:

- `isLoadingViews`
- `mainSplitView`
- `channelPaneView`
- `chatPaneView`

XIB/root view outlets:

- `messageEntryContainerView`
- `channelViewHeader`
- `chatViewHeader`
- `userInfoView`
- `serverViewScroller`
- `channelViewScroller`
- `chatViewScroller`
- `messageEntryViewScroller`
- `tagSelectionViewScroller`
- `pendingAttachmentViewScroller`
- `serversScrollView`
- `channelsScrollView`
- `tagSelectionScrollView`
- `messageEntryTextView`
- `messageEntryScrollView`
- `chatScrollView`
- `myUserAvatarImage`
- `myUsernameTextField`
- `myDiscTextField`
- `attachButton`
- `serverLabel`
- `chatHeaderImage`
- `chatHeaderLabel`
- `pendingAttachmentsScrollView`
- `typingStatusTextField`
- `replyToView`
- `replyToTextField`

Child-controller references:

- `serverNavigationController`
- `mainHeaderController`
- `directMessageController`
- `messageSearchController`
- `pinsController`
- `memberListController`
- `userProfileController`
- `messageReadStateController`
- `threadController`
- `channelNavigationController`
- `messageComposerController`
- `messagePresentationController`

External delegate:

- `delegate`

## Remaining protocol conformances

All 13 conformances route system or child-controller events at the composition
boundary:

- `DLControllerDelegate`
- `DLUserDelegate`
- `DLServerNavigationControllerDelegate`
- `DLChannelNavigationControllerDelegate`
- `DLMemberListControllerDelegate`
- `DLThreadControllerDelegate`
- `DLMessageSearchControllerDelegate`
- `DLPinsControllerDelegate`
- `DLMessageComposerControllerDelegate`
- `DLDirectMessageControllerDelegate`
- `DLMessagePresentationControllerDelegate`
- `DLMainHeaderControllerDelegate`
- `NSSplitViewDelegate`

Notably absent are the old table, outline, chat-row and text-view protocol
conformances. Those belong to their dedicated owners.

## Dead legacy UI audit

The following paths were classified **DEAD** after checking source references,
allocations, XIB owners and Xcode project membership. Their replacements own
the active programmatic row paths.

- `ServerItemViewController.h/.m/.xib` — replaced by `DLServerNavigationController`
- `ChannelItemViewController.h/.m/.xib` — replaced by `DLChannelNavigationController`
- `DirectMessageItemViewController.h/.m/.xib` — DM rows share `DLChannelNavigationController`

They were removed from the source tree, Resources/Sources phases and project
groups. `ChatItemViewController` remains active and is the shared guild/DM/replay
message renderer.
