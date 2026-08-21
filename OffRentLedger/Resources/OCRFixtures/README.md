# OCR fixtures

Synthetic recognised-text samples used by `DocumentTextParserTests` (SwiftPM, runs anywhere) and
by `OffRentLedgerTests` (Xcode).

Every file here is **invented for this repository**. The company names, addresses, agreement
numbers, unit numbers and amounts are fictional. No text is transcribed from a real vendor's
contract or invoice, and none is copied from any rental company's paperwork. They are written to
look like what Vision's text recogniser returns — one line per recognised line, header decoration
included, occasional character-level noise — rather than like clean data.

`*.lowconf` in a filename means the fixture is paired with a low `averageRecognitionConfidence` in
the test, to exercise the rule that a marginal scan must not produce preselected suggestions.
