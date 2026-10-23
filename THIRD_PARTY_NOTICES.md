# Third-party notices

MoonODS original implementation is under MIT (`LICENSE`). Its license does not replace dependency or specification licenses.

| Component | Use | License/source distribution |
|---|---|---|
| MoonBit bundled core | Buffers, UTF-8 and collections | Apache-2.0; original copy in licenses/moonbit-core-Apache-2.0.txt; SDK not bundled |
| moonbit-community/flate 0.9.0 | Direct runtime dependency of the current candidate: CRC32 and incremental inflate | Apache-2.0; unchanged source archive vendor/flate-0.9.0.zip retains its original LICENSE; listed in DEPENDENCIES.lock.json |
| moonbit-community/zipc 0.2.2, flate 0.2.0 | Historical only: used by the published 0.2.0 release; NOT used by the current candidate | Apache-2.0; unchanged archives vendor/zipc-0.2.2.zip and vendor/flate-0.2.0.zip kept for history, not in DEPENDENCIES.lock.json |
| moonbitlang/mbtexcel 0.3.0 | Test fixture only (fixtures/mbtexcel-consumer); not a runtime dependency | Resolved from the registry; see its upstream license |
| OASIS ODF 1.3 specifications/RNG | Standards reference and external verification | OASIS Open copyright; fetched unchanged for tests, not distributed as MIT source |
| odfpy 1.4.1 | Independent test reader | Upstream Apache/GPL/LGPL notices (file-dependent); installed verifier only, not redistributed in this source package |
| lxml 6.0.2 | Relax NG verification | BSD-style upstream with separate bundled-library notices; installed verifier only |
| defusedxml 0.7.1 | odfpy test dependency | PSF license; installed verifier only |

The exact bundled flate 0.9.0 archive and every contained source file have recorded SHA256 values in DEPENDENCIES.lock.json (the historical zipc/flate 0.2.0 archives were hashed in earlier releases and are not part of the current lock). Original LICENSE copies are also supplied in licenses. No archive file was modified; no upstream NOTICE file was present in these exact archives. No competitor implementation or fixtures were copied.

All sales, experiment, formula, edge and compatibility diagnostic datasets are synthetic fixtures created for this project and licensed with its original code. They contain no personal records.
