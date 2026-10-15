# Local development testing

This is a current-macOS preview environment, not evidence of Mountain Lion or
Mavericks compatibility. It never uses Discord credentials when a fixture is
selected.

## DevLocal

`Legacy Discord Dev` uses the `DevLocal` configuration. On this Apple Silicon
Mac it builds arm64 with `LEGACY_DISCORD_LOCAL_DEV=1`; production Debug and
Release remain x86_64 with a 10.7 deployment target.

```sh
./scripts/local-build-dev.sh
./scripts/local-build-login-preview.sh
./scripts/local-build-all.sh
./scripts/local-run-dev.sh --fixture channel-basic
./scripts/capture-ui-dev.sh channel-basic --window-size 720x520
```

Available replays: `channel-basic`, `channel-message-states`. These use the
same message view, controller, and layout path as the logged-in application;
only the data source is synthetic. Unknown names are
rejected by the scripts. Fixture mode does not create `DLController`, access
Keychain, log in, or open HTTP/WebSocket connections.

The replay window starts at 960x640 points. The supported deterministic launch
sizes are `720x520`, `960x640`, and `1280x800`; unsupported values are rejected
by the local scripts. The minimum replay window size is 720x520 points.

## Local login preview

`Legacy Discord.app` is built separately for manual login verification:

```sh
./scripts/local-build-login-preview.sh
./scripts/local-run-login-preview.sh
```

Its source path is the normal production Debug path: it may access Keychain and
Discord after launch. On this Apple Silicon Mac it is an x86_64 app run through
Rosetta. Current Xcode cannot link a 10.7 target, so the script applies a
command-line-only 10.13 deployment override and writes only to
`artifacts/local-login-preview/`. It does not alter the project Debug setting,
and it is not a Mountain Lion/Mavericks build or compatibility result.

Use `./scripts/local-build-all.sh` to build both the offline fixture app and
the login preview in one command. The two products are kept in separate
artifact directories and never overwrite each other or `build/Debug`.

## Regression run

```sh
./scripts/test-local-regression.sh
./scripts/test-local-regression.sh --quick
./scripts/test-local-regression.sh --screenshots
./scripts/test-local-regression.sh --fixture channel-basic
```

The full run checks source, builds DevLocal and the isolated login preview,
captures every fixture at 960x640,
and checks for newly-created DevLocal crash reports. `--screenshots` expands
capture coverage to 720x520, 960x640, and 1280x800. `--quick` skips only source
syntax verification. Results, logs, screenshots, and a manifest are placed under
`artifacts/local-dev/regression/`; generated files are ignored by Git.

Fixture screenshots are rendered by the app into PNG files and do not require
Screen Recording permission. Desktop captures or UI scripting may still need
Screen Recording and Accessibility permission in macOS System Settings.
When `--output` is relative, `capture-ui-dev.sh` resolves it from the repository
root before launching the GUI application.

## Fallback boundary

DevLocal is a preview-only configuration. It is not Mountain Lion/Mavericks
validated and must not be used to claim legacy compatibility. Production
Debug/Release retain their original architecture and deployment target; a
reviewed revert can therefore remove only the DevLocal configuration and its
`LEGACY_DISCORD_LOCAL_DEV` branch without changing production behavior.
