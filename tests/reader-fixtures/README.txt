Checkout-only reader acceptance fixtures. See docs/REVIEW_FOLLOWUP_20261015_ZH.md.
All FODS/XML/ZIP control data are synthetic and MIT-licensed with this repository.
external/libreoffice-dev-types.ods is actual independently produced LibreOfficeDev
output from source/types.fods. It is not produced by MoonODS, not an official
LibreOffice corpus file, not a stable LibreOffice compatibility result.
controls-manifest.json contains intended future expectations; EVERY MoonODS
reader execution remains NOT_RUN. Do not load hostile controls in Office apps.
External formula cache was recalculated by Calc (99 -> 3), not by MoonODS.

2026-10-18 update: the NOT_RUN status above is superseded for the examples/ods_tool
path. All 12 controls and the external sample were executed through the public API
on a scratch copy where Int32 was replaced by Int (the locked SDK moonc v0.10.14
cannot compile the unmodified candidate). Outputs: evidence/review-20261018/.
