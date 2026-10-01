# Third-party notices

MoonODS original implementation is under MIT (`LICENSE`). Its license does not replace dependency or specification licenses.

| Component | Use | License/source distribution |
|---|---|---|
| MoonBit bundled core | Buffers, UTF-8 and collections | Apache-2.0; original copy in licenses/moonbit-core-Apache-2.0.txt; SDK not bundled |
| moonbit-community/zipc 0.2.2 | CRC32 for STORED entries | Apache-2.0; unchanged source archive vendor/zipc-0.2.2.zip retains its original LICENSE |
| moonbit-community/flate 0.2.0 | zipc transitive dependency | Apache-2.0; unchanged source archive vendor/flate-0.2.0.zip retains its original LICENSE |
| OASIS ODF 1.3 specifications/RNG | Standards reference and external verification | OASIS Open copyright; fetched unchanged for tests, not distributed as MIT source |
| odfpy 1.4.1 | Independent test reader | Upstream Apache/GPL/LGPL notices (file-dependent); installed verifier only, not redistributed in this source package |
| lxml 6.0.2 | Relax NG verification | BSD-style upstream with separate bundled-library notices; installed verifier only |
| defusedxml 0.7.1 | odfpy test dependency | PSF license; installed verifier only |

The exact bundled zipc/flate archives and every contained source file have recorded SHA256 values in DEPENDENCIES.lock.json. Original LICENSE copies are also supplied in licenses. No archive file was modified; no upstream NOTICE file was present in these exact archives. No competitor implementation or fixtures were copied.

All sales, experiment, formula and edge datasets are synthetic fixtures created for this project and licensed with its original code. They contain no personal records.
