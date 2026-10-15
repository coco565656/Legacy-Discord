# Discord Messenger feature comparison

Reference: [DiscordMessenger/dm](https://github.com/DiscordMessenger/dm),
checked on 2026-10-01. Its Windows implementation is MIT-licensed. This Mac
project remains based on Discord Lite under GPL-3.0; the additions below are
native AppKit implementations rather than copied Win32 code.

The comparison concerns functions and behavior only. Visual design follows the
official Discord client's dark theme and layout, implemented in AppKit, as
decided by the user on 2026-10-15 (superseding the 2026-10-01 note that
pointed to native Mac controls).

| Discord Messenger feature | Legacy Discord status |
| --- | --- |
| Servers, direct messages, message viewing and sending | Already present |
| Attachments, uploads and downloads | Already present |
| Message editing, deletion and replies | Already present |
| Typing indicator | Already present |
| Member list and pinned messages | Already present |
| Embeds and profile images | Already present, with known rendering work remaining |
| Private notes on users | Added to the expanded profile in this pass |
| External link warning | Added for message text links in this pass |

The note control uses Discord Messenger's GET and PUT `/users/@me/notes/{id}`
flow. A missing note (HTTP 404) is shown as an empty editable note. Other load
errors leave the control read-only; save errors retain the edited text and
offer a retry. The note is saved only when **Save Note** is pressed. Live
account verification is still required because this endpoint is not part of
the public Discord API documentation and may change.

The next useful parity work is to stabilize the existing shared message
renderer and finish the incomplete embed and attachment states. Those areas
already have native owners and should be improved there, with Snow Leopard
compatibility and offline replay coverage, rather than replaced with a second
UI or a web wrapper.
