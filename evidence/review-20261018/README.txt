HISTORICAL / SUPERSEDED (kept for history, 2026-10-18, produced by moonf before integration).
Do not read these files as the current state of the candidate.

What these files are:
- Toolchain: moon 0.1.20260920 (914d7da), moonc v0.10.14+7d59c7ec9 (the OLD SDK), Node v24.18.0.
- Start commit: 9b3801cc1db978b017b075dc50bda44acf6c5659 (review/moonbit-20261015-sync).
- On that unmodified old-baseline tree with the OLD SDK, `moon check` failed: "The type Int32 is undefined" (25 uses).
- SUGGESTED-moonods-core-int32-to-int.patch: a suggestion applied ONLY to a scratch copy; it is
  NOT applied and NOT needed: the official SDK 0.10.15 provides Int32 and the integrated candidate compiles on it.
- ods-scratch-int-test-{js,wasm-gc}.log: 166/166 on that scratch copy (Int rewrite, old workspace). It does NOT
  prove the current candidate.
- ods-tool-external.log / ods-tool-controls.log: examples/ods_tool outputs on that scratch copy. Log paths refer to it.

Current evidence (integration round, same day) is NOT stored here. On the official SDK
(moonc v0.10.15+943464bfa, moon 0.1.20261012) scripts/acceptance.py passes all 22 steps:
JS 65/65 and Wasm GC 65/65 (core 61 + 4 same-module consumer tests per backend). See README.md.
