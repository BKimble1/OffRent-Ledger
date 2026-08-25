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

## What each one is for

| File | Why it exists |
| --- | --- |
| `contract_skidsteer_clean.txt` | The happy path: every label present and spelled as expected. |
| `contract_excavator_messy.txt` | A second vendor's layout, with `Daily Rate 410.00` and no colons. |
| `contract_minimal.txt` | A contract carrying almost nothing, to prove the parser does not guess. |
| `contract_split_labels.txt` | A third layout where the label and its value are on **different lines**, and the rate table is a dotted-leader list. |
| `invoice_matching.txt` | An invoice that agrees with the confirmed terms. |
| `invoice_extra_day.txt` | An invoice billing one day past the confirmation. |
| `invoice_with_fees.txt` | Every supported charge category on one document. |
| `invoice_noisy_lowconf.txt` | Paired with a low recognition confidence, to prove nothing is preselected. |
| `invoice_multipage_ocr_noise.txt` | A two-page invoice with the classic OCR confusion of `0` for `O`, to prove a mis-read digit does not become a confident amount. |
| `contract_abbreviated_serial.txt` | A contract whose serial number is printed `S/N 4TNV88-1234` rather than spelled out, which is how nearly every ticket and plate writes it. |
| `invoice_waiver_abbreviation.txt` | An invoice billing the optional damage waiver as `RPP (14%)`, and heading itself `INVOICE NO 44821` with no colon. Carries a `MIDWAY` line item so that `DW` matching inside a longer word stays caught. |
| `unrelated_residential_lease.txt` | The **negative test**. OCR reads it perfectly; the extractor must find nothing, because nothing on it is a machine, a rate or a rental date. |
