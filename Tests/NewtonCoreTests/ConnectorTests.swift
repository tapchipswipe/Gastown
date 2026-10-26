import Testing
import Foundation
@testable import NewtonCore

struct ConnectorTests {
    @Test func testLumenImportSkipsInvalidLinesAndUsesStableIdentity() throws {
        let json = #"{"ts":"2026-10-24T12:00:00Z","kind":"appFocus","payload":{"type":"appFocus","appFocus":{"appName":"Xcode","bundleID":"com.apple.dt.Xcode"}}}"#
        let input = Data((json + "\ninvalid\n" + json + "\n").utf8)
        let batch = try LumenImport.parse(input)
        #expect(batch.skipped == 1)
        #expect(batch.events.count == 2)
        #expect(batch.events[0].id == batch.events[1].id)
        #expect(batch.events[0].title == "Xcode")
        #expect(batch.events[0].source == "Lumen · appFocus")
    }

    @Test func testCanonicalLumenIdentityDoesNotDependOnJSONKeyOrder() throws {
        let a = #"{"ts":"2026-10-24T12:00:00Z","kind":"appFocus","payload":{"appFocus":{"appName":"Safari"}}}"#
        let b = #"{"payload":{"appFocus":{"appName":"Safari"}},"kind":"appFocus","ts":"2026-10-24T12:00:00Z"}"#
        #expect(try LumenImport.parse(Data(a.utf8)).events.first?.id == LumenImport.parse(Data(b.utf8)).events.first?.id)
    }

    @Test func testScreenpipeDecodesOCRAndAudioWithoutInventingTimes() throws {
        let json = #"{"data":[{"type":"OCR","content":{"frame_id":42,"timestamp":"2026-10-24T12:00:00.123Z","app_name":"Safari","text":"Original evidence"}},{"type":"Audio","content":{"chunk_id":9,"timestamp":"2026-10-24T12:00:00Z","transcription":"A real conversation"}},{"type":"OCR","content":{"frame_id":43,"text":"Missing timestamp"}}]}"#
        let rows = try ScreenpipeClient.decode(Data(json.utf8))
        #expect(rows.count == 2)
        #expect(rows[0].id == "screenpipe:ocr:42")
        #expect(rows[1].detail == "A real conversation")
    }

    @Test func testScreenpipeRejectsUnexpectedEnvelope() {
        #expect(throws: (any Error).self) { try ScreenpipeClient.decode(Data(#"{"error":"unauthorized"}"#.utf8)) }
    }
}
