# Known issues

Only reproducible issues belong here. Do not add remembered or suspected
problems without evidence.

## Reproduced issues

None recorded yet.

## Resolved during local testing

```text
Issue ID: LD-2026-001
Found: 2026-08-25
Priority: P1 (local regression fixture unavailable)
Screen: channel-basic fixture
Reproduction steps: Run ./scripts/test-local-regression.sh --quick after adding channel-message-states.
Reproduction rate: 2/2
Expected result: channel-basic writes its PNG and exits within the capture timeout.
Actual result: no PNG was written; the application stayed open.
Screenshot: not produced (expected output path is in regression fixture log)
Log: artifacts/local-dev/regression/20260825-115029/logs/fixture-channel-basic.log
Crash report: none
sample result: channel-basic.sample.txt showed the main thread waiting for events.
Cause: channel-basic had three message strings but the shared authors array had four entries.
Fix commit: pending user validation
Regression test: test-local-regression.sh includes channel-basic in full and quick runs.
Legacy OS status: NOT APPLICABLE (DevLocal-only code)
```

```text
Issue ID: LD-2026-002
Found: 2026-08-25
Priority: P1 (local screenshot capture unavailable with a relative output path)
Screen: DevLocal capture script
Reproduction steps: Run capture-ui-dev.sh with --output artifacts/local-dev/probes/example.png.
Reproduction rate: 2/2
Expected result: the PNG is saved beneath the repository artifact directory.
Actual result: no PNG was written because the launched GUI application's working directory did not resolve the relative output path.
Screenshot: not produced (capture output path was unresolved)
Log: terminal output from 20260825-125848 probe
Crash report: none
sample result: channel-basic-720x520.sample.txt showed the main thread waiting for events, not stalled.
Cause: capture-ui-dev.sh passed relative paths directly to open(1).
Fix commit: pending user validation
Regression test: test-local-regression.sh --screenshots uses absolute artifact paths; capture-ui-dev.sh now normalizes relative paths.
Legacy OS status: NOT APPLICABLE (DevLocal-only script)
```

## Entry template

```text
Issue ID: LD-YYYY-NNN
Found: YYYY-MM-DD
Priority: P0 | P1 | P2 | P3
Screen:
Reproduction steps:
Reproduction rate:
Expected result:
Actual result:
Screenshot:
Log:
Crash report:
sample result:
Cause:
Fix commit:
Regression test:
Legacy OS status: NOT TESTED | PASS | FAIL
```
