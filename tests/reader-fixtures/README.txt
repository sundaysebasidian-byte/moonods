Checkout-only bounded reader fixtures, not runtime package assets.
All FODS/XML/ZIP controls are synthetic and MIT-licensed with this repository.
external/libreoffice-dev-types.ods is actual independently produced LibreOfficeDev
output from source/types.fods. It is not a real business record, official corpus
fixture or stable LibreOffice result. external/source.json preserves original
producer-time metadata; its historical NOT_RUN field is not current test status.

scripts/verify_ods_tool.py exercises the external sample and 12 controls.
scripts/verify_reader_compat.py converts the synthetic source/rich-text.fods with
an existing LibreOffice and checks output independently, including typed edits,
CSV, stable headless resave and library reread. See docs/READER_COMPAT.zh-CN.md.
Controls must never be opened in Office. Optional official LibreOffice/core
basic-cell-content.ods is hash-checked and kept outside this repository; it is
not relabelled MIT or redistributed. Results apply only to their recorded source
and tool versions, not to every Office application or arbitrary spreadsheets.

source/extended-types.fods is original MIT-licensed synthetic data for currency,
percentage, signed day/time duration, datetime and exact-width experiments.
scripts/verify_extended_compat.py uses an existing stable LibreOffice to produce
the actual ODS input, performs a typed amount edit, checks raw decimal/type/unit
attributes and official ODF schemas, then resaves and rereads. It records the
explicit-offset timestamp loss in LibreOffice rather than treating it as a pass
for timezone preservation. No customer data or newly redistributed official
binary fixture is included.
