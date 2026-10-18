# Bounded typed ODS workflow: first-round candidate

This is the first-round record. Current follow-up changes and results are in [round two](TYPED_READER_ROUND2_20261015.md).

This continues `faba6eadabdc036bf5cd925fe36db0a6bced7139` from the verified recovery bundle. It changes the library, rather than treating fixture preparation as a reader. The published 0.2.0 artifact is unchanged; no push, Actions, registry publication or resubmission was performed.

## New usable path

```mbt
let imported = @ods.read_ods(bytes, allow_formatting_loss=true)
let workbook = imported.workbook()
let sheet = workbook.sheet(0).unwrap()
sheet.set(1, 0, @ods.Cell::new(Number(8.5)))
let edited = workbook.to_ods()
for diagnostic in imported.diagnostics() {
  // Present diagnostic.code/message and zero-based sheet/row/col to the user.
}
```

`read_ods` defaults to refusal. The explicit option accepts data-only import, including loss of source formatting, numeric display text, application metadata, view settings and thumbnails. It is not an arbitrary ODS preservation editor. Typed values, empty-string vs empty, supported text whitespace, bounded row/column repeats, rectangular merges, formula text and existing typed cache are retained. Formulas are never evaluated or refreshed after edits; every formula produces `FORMULA_CACHE_NOT_RECALCULATED`. Cell style loss receives a sheet/row/col diagnostic; sheet/row/column style loss uses `-1` for the non-cell axis. Global `DATA_ONLY_IMPORT` discloses the common loss policy. Diagnostics are capped at 8,192, after which import rejects. Failed imports never return a partial workbook.

`Workbook.sheet`, `Sheet.dimensions`, `merge_span` and `is_covered` expose safe public traversal for downstream consumers. Errors in typed cells and repeat counts identify known sheet/row/column. Unsupported currency, percentage, timestamps, missing formula caches, LibreOffice error caches, conflicting typed attributes, rich text/hyperlinks, annotations, drawings, nonempty named expressions and unknown structural elements are rejected rather than converted or dropped.

## Resource and syntax contract

- Input at most 32 MiB, 128 ZIP32 entries, 4 MiB cumulative actual decompressed bytes across all entries. Streaming `flate.Inflater.step` enforces the actual bound, including forged sizes; the unbounded convenience decoder is not used.
- Validates local/central headers, signed data descriptors, compression flags, CRCs for every entry, duplicate paths, gaps/overlaps, ZIP64/encryption and UTF-8. A fixed path allowlist permits standard content/styles/manifest/metadata/settings/thumbnail entries and an empty `Configurations2/`; macros, signatures and other assets are rejected.
- XML is a deliberately strict UTF-8/XML 1.0 subset: namespace-expanded names, 32 nested-element depth, 65,536 elements, 64 attributes per element, 256-character names and 32,767 UTF-16 text/attribute units. DTD, custom entities, comments, CDATA and nondeclaration processing instructions are unsupported and fail closed. Decimal/hex character references and predefined entities are supported, with invalid code points rejected.
- Existing writer limits remain: 32 sheets, 1,024 rows / 128 columns, 65,536 rendered cells per sheet, 262,144 per workbook, 2 MiB text units per sheet / 4 MiB per workbook, and 256 merges per sheet. Import checks aggregate budgets during construction, rather than after building all 32 sheets. A failing cell may allocate its own bounded value before rejection; no unbounded pre-allocation claim is made.
- Explicit empty rows and declared empty columns retain their dimensions. Empty trailing ODS ranges beyond these bounds are rejected; they are not silently trimmed.
- Only Gregorian `YYYY-MM-DD` dates and finite IEEE-754 doubles. Formula syntax is limited to existing `of:=` storage validation and the correct namespace; no external-reference safety or evaluation guarantee.

## Evidence and attribution

Current SDK: official installed `moon 0.1.20261012 (748b63c)`, `moonc v0.10.15+943464bfa`, Node v24.19.0. Bundled zipc 0.2.2 / flate 0.2.0 archive hashes remain unchanged. This differs from the historical release lock. `scripts/acceptance.py` was actually run and failed at `Compiler differs from TOOLCHAIN.lock`; that gate was not loosened. Current review checks are separate and must not be called full release acceptance.

Run with an already installed SDK on PATH and `MOON_HOME` set:

```sh
python3 scripts/restore_deps.py
python3 scripts/verify_reader_review.py
# Optional, only when an existing application is available:
python3 scripts/verify_reader_review.py --soffice /path/to/soffice
```

The checked-in `moon.work` binds only this checkout and exact restored vendor sources for local review. It is excluded from runtime packaging; it is not a registry-consumer proof.

Evidence lives in `evidence/typed-reader-20261015/`:

- JS and Wasm GC check/build; 51/51 MoonODS core tests (24 new) and 156/156 full-workspace tests on each backend. Workspace totals include dependency tests. The independent reviewer ran an intentionally earlier 48-test baseline plus six independent regressions: 54/54 on each backend against the final fixed implementation. These counts are separate, not added together.
- All 12 existing controls execute through the actual public reader. Only typed-prefix-alias is accepted; the eleven hostile/unsupported fixtures reject.
- The frozen LibreOfficeDev producer sample is read by MoonBit, edited (Types row 1 / col 0 from 7.5 to 8.5), written and reread. This is the same single producer family, not an additional independent source.
- A separate copied MoonBit module uses only public APIs and generates an actual edited ODS. An independent Python/lxml semantic comparison verifies the intended single edit and preservation of other supported values, whitespace, empty string, repeat values, merges and formula/cache.
- Installed LibreOfficeDev 26.8 alpha opens and natively resaves this edited output under an isolated temporary profile. Independent typed comparison checks the saved result. This is headless Dev evidence only, not stable LibreOffice, GUI or Excel evidence. Fontconfig warnings are retained.
- Independent review found malformed declarations, raw `]]>`, QName/namespace rules, calcext error coercion, empty-dimension shrinkage and incomplete repeat-error context. A second independent review caught truncated merge-span shrinkage, XML-declaration entity references, language-only numeric underscores and CLI sheet-order loss when a later sheet was named Sheet1. All were fixed with regressions and independently retested; aggregate limits are checked during import. This is tested evidence, not a formal security proof.

## Remaining gates

The initial reviewer correctly noted that existing ODS readers already exist (including markitdown). The new differentiator is the tested typed edit/write path with explicit loss/error policy, not a claim to be the first reader. Reviewer acceptance of that value is still unknown.

A direct combined mbtexcel 0.3.0 consumer fails dependency resolution/type checking: it requires flate 0.9.0, whereas locked zipc 0.2.2 matches the old one-field `InflateError` constructor. No vendored dependency was patched. A separate-process CLI bridge now passes through the actual public APIs: MoonODS → typed JSON → mbtexcel write/read. It verified 24 typed cells, 2 sheets, one merge, empty-string vs blank, Boolean and date semantics; a separate OOXML check confirms the data. Formula-containing input is rejected by default; explicit cache-only export emits FORMULA_DROPPED per cell. 1900-01-01 maps to serial 1 and pre-1900 dates reject. The later-Sheet1 regression preserves source order. Its portable source/evidence companion is `ods-mbtexcel-public-bridge.tar.gz`; this is CLI interoperability, not same-module compatibility, and does not patch either library's locked dependencies.

Stable LibreOffice, Excel/Numbers/WPS, full legacy locked acceptance, schema validation of the new imported-output subset, additional external producer families and broader ODF compatibility remain separate gates. This candidate is not declared ready for resubmission.
