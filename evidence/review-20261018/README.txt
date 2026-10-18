Local evidence, 2026-10-18, produced by moonf. NOT remote CI, NOT registry.
Toolchain: moon 0.1.20260920 (914d7da), moonc v0.10.14+7d59c7ec9, Node v24.18.0.
Start commit: 9b3801cc1db978b017b075dc50bda44acf6c5659 (review/moonbit-20261015-sync).
- On the unmodified tree `moon check` fails: "The type Int32 is undefined" (25 uses).
- SUGGESTED-moonods-core-int32-to-int.patch: Int32->Int in reader*.mbt/xml.mbt, applied ONLY
  to a scratch copy. It is a suggestion for the core owner and is not applied to this tree.
- ods-scratch-int-test-{js,wasm-gc}.log: 166/166 on that scratch copy.
- ods-tool-external.log / ods-tool-controls.log: examples/ods_tool on the external sample
  and the 12 hostile controls (strict and accept-loss) on that scratch copy.
Log paths inside the logs refer to the scratch copy.
