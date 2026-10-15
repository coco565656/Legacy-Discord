# QA checklist

Status values: PASS, FAIL, NOT TESTED, LEGACY OS REQUIRED, NOT APPLICABLE.
Current-macOS results are preview evidence only.

| Status | Test target | Procedure / expected result | Fixture | Automated | Current macOS | 10.6-10.8 / 10.9 |
| --- | --- | --- | --- | --- | --- | --- |
| NOT APPLICABLE | Retired independent fixtures | The former `friends` and `settings` hand-built fixture windows are excluded: they did not use the live rendering path. | none | No | No | Not applicable |
| PASS | Replay launch: basic channel | Capture `channel-basic`; it must use `DLMainWindowController`, `ChatScrollView`, and `ChatItemViewController`. | replay-basic | Yes | PASS | Snow Leopard PASS at 720x520 for the shared replay path |
| PASS | Replay launch: message states | Capture `channel-message-states`; edited, reply, Unicode/reaction, and compact rows use the shared path. | replay-message-states | Yes | PASS | Snow Leopard PASS at 720x520; live login pending |
| PASS | Deterministic message geometry | Capture the four `channel-layout-*` replays; calculated/displayed text height and expected/actual row height must match. | text, unbroken, states, attachment | Yes | PASS at all three sizes | Snow Leopard attachment PASS at 720x520; other combinations pending |
| PASS | Offline boundary | Launch each replay; no login, Keychain, or network request may be initiated. | all current replays | Partial | PASS | Snow Leopard attachment replay PASS |
| NOT TESTED | Login preview | Launch `local-run-login-preview.sh`; normal login window appears and may use the user's own credentials. | real login | Build and launch smoke | Build PASS | Snow Leopard launch remained alive for five seconds; authentication and graceful quit remain NOT TESTED |
| PASS | 720x520 captures | Run `test-local-regression.sh --screenshots`; inspect affected replay PNGs for overlap or clipping. | all 16 replays | Yes | PASS; selected screenshots inspected | Channel, picker and profile captures inspected on Snow Leopard; complete legacy matrix pending |
| PASS | 960x640 captures | Run `test-local-regression.sh --screenshots`; inspect affected replay PNGs for pane, row and composer alignment. | all 16 replays | Yes | PASS; selected screenshots inspected | channel-basic inspected on Snow Leopard; Twemoji rendering remains required |
| PASS | 1280x800 captures | Run `test-local-regression.sh --screenshots`; inspect affected replay PNGs for pane and composer alignment. | all 16 replays | Yes | PASS; selected screenshots inspected | LEGACY OS REQUIRED |
| NOT TESTED | DM variations | Long names, emoji-only, attachment/sticker and compact pane behavior. | fixture needed | No | Partial | Yes |
| PASS | Channel navigation baseline | `channel-navigation` uses the production server table, channel outline, row cells and selection path; inspect category, text/voice rows and unread badges. Many-channel scrolling and live switching remain manual. | channel-navigation | Yes | PASS at all three sizes | Snow Leopard PASS at 720x520 after legacy-scroller visible-width correction |
| NOT TESTED | Message hover / scroll | No stale or clipped hover after scroll or channel switch. | fixture needed | No | Partial | Yes |
| NOT TESTED | Search / thread / member / profile | Open, switch, move results, and confirm no main-thread stall. | fixture needed | No | Partial | Yes |
| PASS | Deterministic Composer state | Exercise production-path multiline text, reply, attachment, emoji insertion and picker, mention candidates, typing and sticker presentation. This does not cover IME, paste, undo, edit or drag/drop. | eight `composer-*` replays | Yes | PASS at all three sizes | Mention, emoji picker and sticker fallback opened on Snow Leopard; Unicode glyph rendering remains incomplete |
| FAIL | Standard emoji glyphs on Snow Leopard | Open the production emoji picker using an offline fixture and inspect every visible cell. | composer-emoji-picker | Partial | PASS | Snow Leopard FAIL: most cells show missing-glyph boxes; Twemoji images required |
| PASS | Production build metadata | Build with the Snow Leopard toolchain and confirm x86_64, 10.6 SDK/deployment settings and bundled-library load paths. | none | Partial | Preview only | Snow Leopard Xcode 3.2.6 build PASS; Lion/Mountain Lion/Mavericks remain required |
| LEGACY OS REQUIRED | Production launch and performance | Exercise the same x86_64 application on 10.6.8, 10.7.5, and 10.8.5; test 10.9.5 separately where practical. | real or safe fixture | No | No | Required |
| LEGACY OS REQUIRED | Keychain compatibility | Log in, relaunch, restore the session, log out, and confirm the generic-password item is removed. | real login | No | Preview only | Required |
| LEGACY OS REQUIRED | Compatibility popovers | Open profile, emoji, and sticker UI; Snow Leopard must use the panel fallback and Lion or later the native popover. | real or safe fixture | Partial | Native path only | Snow Leopard profile, emoji and sticker panels open; Lion/Mountain Lion path remains required |

For a failure, create an entry in `KNOWN_ISSUES.md` only after a reproducible
run has saved the screenshot, log, crash report, or sample named in the entry.
