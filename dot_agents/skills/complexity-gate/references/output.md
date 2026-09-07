`complexity-gate check --changed` reports counts and at most 20 paths. Follow its `DETAILS` command one file at a time, such as `complexity-gate check --changed --verbose <file>`.

Detailed failures read `FAIL path:line name metric value > limit`. Metrics include `complexity`, `depth`, `lines`, and `params`. Use the reported limits and measurements, not hand estimates.

`UNVERIFIED path` means the binary has no grammar for that language. Report the gap; do not substitute a manual count or claim it passed.

Where installed, the Stop hook reruns the changed check and blocks on remaining FAIL lines. Resolve the violations rather than bypassing the hook.
