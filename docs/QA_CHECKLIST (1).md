# QA checklist

Status values: PASS, FAIL, NOT TESTED, LEGACY OS REQUIRED, NOT APPLICABLE.
Current-macOS results are preview evidence only.

| Status | Test target | Procedure / expected result | Fixture | Automated | Current macOS | ML/Mavericks |
| --- | --- | --- | --- | --- | --- | --- |
| NOT APPLICABLE | Retired independent fixtures | The former `friends` and `settings` hand-built fixture windows are excluded: they did not use the live rendering path. | none | No | No | Not applicable |
| NOT TESTED | Replay launch: basic channel | Capture `channel-basic`; it must use `DLMainWindowController`, `ChatScrollView`, and `ChatItemViewController`. | replay-basic | Yes | Pending | Not applicable |
| NOT TESTED | Replay launch: message states | Capture `channel-message-states`; edited, reply, Unicode/reaction, and compact rows use the shared path. | replay-message-states | Yes | Pending | Not applicable |
| NOT TESTED | Offline boundary | Launch each replay; no login, Keychain, or network request may be initiated. | all current replays | Partial | Pending | Not applicable |
| NOT TESTED | Login preview | Launch `local-run-login-preview.sh`; normal login window appears and may use the user's own credentials. | real login | Build only | Yes | Yes |
| NOT TESTED | 720x520 layout | Run `test-local-regression.sh --screenshots`; inspect both replay PNGs for overlap or clipping. | all current replays | Yes | Pending | No |
| NOT TESTED | 1280x800 layout | Run `test-local-regression.sh --screenshots`; inspect both replay PNGs for pane and composer alignment. | all current replays | Yes | Pending | No |
| NOT TESTED | DM variations | Long names, emoji-only, attachment/sticker and compact pane behavior. | fixture needed | No | Partial | Yes |
| NOT TESTED | Channel navigation | Categories, unread state, many channels, resize and drag layout. | fixture needed | No | Partial | Yes |
| NOT TESTED | Message hover / scroll | No stale or clipped hover after scroll or channel switch. | fixture needed | No | Partial | Yes |
| NOT TESTED | Search / thread / member / profile | Open, switch, move results, and confirm no main-thread stall. | fixture needed | No | Partial | Yes |
| NOT TESTED | Input and editing | IME, paste, undo, reply, edit, emoji and drop operations. | fixture needed | No | Partial | Yes |
| LEGACY OS REQUIRED | Production launch and performance | Build and exercise x86_64 application on 10.8.5/10.9.5. | real or safe fixture | No | No | Yes |

For a failure, create an entry in `KNOWN_ISSUES.md` only after a reproducible
run has saved the screenshot, log, crash report, or sample named in the entry.
