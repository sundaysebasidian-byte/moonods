# Non-finite ODF numeric diagnostics

ODF numeric attributes may contain the XML Schema double tokens `INF`, `-INF`, and `NaN`. This library's value model accepts finite binary64 numbers only. These three legal tokens, after XML whitespace collapse, are therefore rejected as unsupported non-finite values, not malformed lexical forms. This change does not implement non-finite values or relax output constraints.

Adjacent invalid spellings (`+INF`, `-NaN`, lowercase forms, embedded whitespace, or NBSP padding) remain lexical errors. Finite overflow and the 1024-unit literal budget remain separately bounded. Float, percentage, and currency use the same numeric reader.

The new regression includes exact diagnostic assertions. Additional review evidence uses actual ODS packages, official ODF 1.3 RNG classification, and the compiled CLI; source-level tests alone do not establish all ODF conformance.
