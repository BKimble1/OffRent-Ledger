import Foundation
import XCTest
@testable import OffRentDomain

final class ZZDiagnosticDump: XCTestCase {
    func testDumpRealisticYardContract() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(
            contentsOf: root.appendingPathComponent("OffRentLedger/Resources/OCRFixtures/contract_yard_realistic.txt"),
            encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let doc = RecognizedDocument(
            rawText: text, lines: lines, linePages: lines.map { _ in 0 },
            averageRecognitionConfidence: 0.95, pageCount: 1)
        let result = DocumentTextParser.parse(doc, kind: .rentalContract, calendar: Calendar(identifier: .gregorian))
        print("### FIELDS EXTRACTED: \(result.suggestions.count)")
        for s in result.suggestions.sorted(by: { "\($0.field)" < "\($1.field)" }) {
            print("###   \(s.field) = \(s.value)  conf=\(String(format: "%.2f", s.confidence))  rule=\(s.provenance.rule)")
        }
        print("### ALL SuggestedField CASES:")
        for f in SuggestedField.allCases { print("###   \(f)") }
    }

    func testDumpRealisticYardInvoice() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(
            contentsOf: root.appendingPathComponent("OffRentLedger/Resources/OCRFixtures/invoice_yard_realistic.txt"),
            encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let doc = RecognizedDocument(
            rawText: text, lines: lines, linePages: lines.map { _ in 0 },
            averageRecognitionConfidence: 0.95, pageCount: 1)
        let result = DocumentTextParser.parse(doc, kind: .vendorInvoice, calendar: Calendar(identifier: .gregorian))
        print("@@@ INVOICE FIELDS: \(result.suggestions.count)")
        for s in result.suggestions.sorted(by: { "\($0.field)" < "\($1.field)" }) {
            print("@@@   \(s.field) = \(s.value)  conf=\(String(format: "%.2f", s.confidence))  rule=\(s.provenance.rule)  <- \(s.provenance.sourceLine)")
        }
    }
}
