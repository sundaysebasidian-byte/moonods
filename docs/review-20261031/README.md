# Review evidence — 2026-10-31

Start with [逐条技术回应](RESPONSE.zh-CN.md) and [implementation-defined范围审计](IMPLEMENTATION_DEFINED.zh-CN.md).

AI-assisted technical evidence, not a human-authored competition application or a submission receipt. No runtime implementation changed here. The ten `.ods` files are wholly synthetic saved outputs from the final DTD acceptance stage. They contain no private business data; they are not all original inputs or a complete conformance test suite.

## Recheck the supplied artifacts

With Python and an existing `lxml` installation, from this directory, supply a separate checkout of the fixed runtime baseline `897c906607e1ec5072e514599e846bdbe6defe3e`:

```sh
python audit_implementation_profile.py --source /path/to/moonods-at-897c906
```

The script verifies 169 original source hashes against runtime baseline `897c906607e1ec5072e514599e846bdbe6defe3e`, then reopens the ten saved outputs for four-part ZIP profile, CRC and XML-vocabulary inspection. Additional documentation files are not part of the original source manifest. Later verification-script fixes are also not part of that historical baseline; pointing at modified sources must fail the original 169-file hash check. Keep this saved-output evidence pinned rather than rewriting its original source identity. It does not execute MoonODS, validate all ODF semantics, or re-run CI/GUI tests. It writes `IMPLEMENTATION_PROFILE_RECEIPT.json`; save the original receipt first if retaining an audit trail.

To re-extract the normative keyword inventory, obtain the four official HTML files from `STANDARD_SOURCES.json` and save them as `standards/part1.html` through `part4.html`, then run:

```sh
python extract_normative_inventory.py
```

The official documents are not redistributed here. Inventory classification records this source audit's judgments; it is not an automatic conformance proof. `implementation-defined` and `implementation-dependent` are not interchangeable.

Three separate review perspectives checked clause extraction, source/evidence alignment and submission/reproducibility wording. Corrections included preserving same-text clauses at different locations, documenting unspecified wrap/default rendering, and distinguishing saved-output reinspection from new runtime tests. No claim of defect-free or fully certified behavior is made.
