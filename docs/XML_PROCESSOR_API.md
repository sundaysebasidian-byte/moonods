# Bounded XML processor and ODS import metadata

This revision extends the data-only importer. It does not claim complete ODF Consumer or Package Consumer conformance, lossless Office roundtrips, general OpenFormula validation, or network entity resolution.

## Encoding, names and DTD

XML 1.0 Fifth Edition Unicode names and namespace aliases are recognized. XML package parts support UTF-8 and BOM-marked UTF-16LE/BE, with matching encoding declarations and strict surrogate validation. ZIP entry names remain UTF-8. A second leading BOM is not silently discarded.

The internal DTD subset is syntax-checked. Read general entities are expanded as bounded attributes or independently balanced content fragments. Default attributes are installed before namespace expansion; declared tokenized attributes are normalized. First declarations win. Parameter entities are not expanded; declarations after an unread parameter entity are not adopted except under the standalone rule. External identifiers are metadata only, never opened.

DTD work, entity nesting, aggregate expansion, XML size/depth/nodes and processor events are bounded. Resource refusal is distinct from an assertion that an input violates the standard. Valid inputs outside the supported data model may still be refused rather than silently lose relevant cell semantics.

## ID metadata

`ImportResult.xml_ids()` returns `Array[XmlIdAssignment]`. `ImportResult.xml_id_diagnostics()` returns `Array[XmlIdDiagnostic]`. Both are defensive array copies.

Each assignment identifies `document_part`, zero-based element preorder index, expanded element and attribute names, normalized `value`, `attribute_type` (`ID`), lexical validity, uniqueness and any read DTD declared type. Invalid IDs still receive ID assignment. ID errors are nonfatal and separate from ordinary bounded loss notices. A wrong xml:id declaration without an instance is reported with `element_index = -1`; it does not create an assignment. Uniqueness is per XML document part, not across the entire package.

## Processing events

`ImportResult.xml_events()` returns a defensive `Array[XmlProcessorEvent]`. Each immutable record contains:

- `document_part`, `sequence`, `location`: document identity, observation ordering and `prolog`, `dtd`, `content` or `epilog` context. Sequence need not restart at zero when a caller supplies an existing collector.
- `kind`, `name`, `data`: event kind, PI target or declaration name, and PI data/message.
- optional `public_id`, `system_id`, `notation`: raw declared identifiers; no resolution or I/O implied.

Event kinds are `PROCESSING_INSTRUCTION`, `NOTATION_DECLARATION`, `UNPARSED_ENTITY_DECLARATION`, `EXTERNAL_SUBSET_NOT_READ`, `PARAMETER_ENTITY_NOT_READ`, `EXTERNAL_ENTITY_NOT_READ`, and `MANIFEST_EXTENSION_NOT_INTERPRETED`. All read notation and unparsed-entity declarations are exposed, including unused declarations. PI target/data are retained across the prolog, internal subset, document content, internal entities and epilog. PI data excludes the separating whitespace and follows external-entity line-end normalization rules.

A referenced external parsed entity cannot supply a trustworthy cell value without being read. Import therefore fails rather than fabricate success. `OdsError.is_unread_xml_dependency()` identifies this refusal or a dependency on unread declarations; it is not a malformed-XML verdict. Ordinary syntax errors and standalone undeclared entities do not receive that classification. An external entity in an attribute or an unparsed entity in content remains an XML constraint error. The public import does not return a partial Workbook on failure.

## Package handling and loss

Public ODS reads require and parse manifest.xml. Structural checks cover entry identity/duplicates, ordinary file coverage and root mimetype agreement. Known XML metadata parts are parsed even when their document semantics are intentionally dropped. Safe additional ZIP files are accepted after the same CRC, size, compression and path checks; they need not appear in a hard-coded filename list. Ordinary files still need manifest entries. Arbitrary files named *.xml are not automatically parsed as XML. Names under META-INF/ containing `signatures` are treated as signature XML regardless of extension; they use the same XML/namespace/xml:id processing and emit SIGNATURE_NOT_VERIFIED plus PACKAGE_PART_DROPPED. No cryptographic validity is asserted.

Foreign manifest elements are parsed structurally, not interpreted, and emit MANIFEST_EXTENSION_NOT_INTERPRETED events plus PACKAGE_EXTENSION_DROPPED notices. Known encrypted content is refused before decoding its ciphertext as XML. Safe arbitrary attachments and embedded files are not rendered, executed, extracted or copied to output. This is not a complete manifest Relax NG validator; such full validation is not a requirement of a nonvalidating consumer.

Metadata observation is not export preservation. `allow_formatting_loss=true` is still required for data-only import; returned diagnostics describe dropped styles and package parts. Formula handling normalizes outer namespace aliases, not arbitrary formula bodies or recalculation.
