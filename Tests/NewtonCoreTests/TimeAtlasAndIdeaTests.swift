import Testing
import Foundation
@testable import NewtonCore

struct TimeAtlasAndIdeaTests {

    @Test func testProtoWireDecoderVarintAndLengthDelimited() throws {
        // Construct a manual proto buffer:
        // Field 1, wire type 2 (length-delimited): length 5, string "hello"
        // key = (1 << 3) | 2 = 10 (0x0A)
        // length = 5
        // bytes = "hello"
        var data = Data([0x0A, 0x05])
        data.append(contentsOf: "hello".utf8)

        // Field 2, wire type 0 (varint): value 42
        // key = (2 << 3) | 0 = 16 (0x10)
        // value = 42 (0x2A)
        data.append(contentsOf: [0x10, 0x2A])

        let fields = try ProtoWireDecoder.decodeFields(from: data)
        #expect(fields.count == 2)
        #expect(fields[0].fieldNumber == 1)
        #expect(fields[0].wireType == .lengthDelimited)
        #expect(fields[0].stringValue == "hello")

        #expect(fields[1].fieldNumber == 2)
        #expect(fields[1].wireType == .varint)
    }

    @Test func testTimeAtlasReaderParsesDateAnalysisAndEvents() throws {
        // Construct a DateAnalysis field (Field 21, wire type 2)
        // Inside: Subfield 2 (date string "2026-10-24"), Subfield 4 (summary string "Deep Work")
        var subData = Data([0x12, 0x0A]) // (2 << 3) | 2 = 18 (0x12), len 10
        subData.append(contentsOf: "2026-10-24".utf8)
        subData.append(contentsOf: [0x22, 0x09]) // (4 << 3) | 2 = 34 (0x22), len 9
        subData.append(contentsOf: "Deep Work".utf8)

        var topData = Data()
        // Key for field 21, wire type 2: (21 << 3) | 2 = 170 (0xAA), varint encoded: 0xAA, 0x01
        topData.append(contentsOf: [0xAA, 0x01, UInt8(subData.count)])
        topData.append(subData)

        let events = try TimeAtlasReader.parseData(topData, fallbackDate: Date())
        #expect(events.count == 1)
        #expect(events[0].source == "Time Atlas")
        #expect(events[0].title == "Deep Work")
        #expect(events[0].detail == "Date: 2026-10-24")
        #expect(events[0].id == "timeatlas:analysis:2026-10-24:deep work")
    }

    @Test func testICloudIdeaStoreSavesAndReadsBack() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NewtonTestIdeas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try iCloudIdeaStore.saveIdea(
            title: "Build Autonomous Video Workflow",
            detail: "Use ScreenCaptureKit to record keyframes and convert to Python scripts.",
            in: tempDir
        )

        let ideas = try iCloudIdeaStore.readReport(from: tempDir).events
        #expect(ideas.count == 1)
        #expect(ideas[0].source == "iCloud Idea")
        #expect(ideas[0].title == "Build Autonomous Video Workflow")
        #expect(ideas[0].detail.contains("Use ScreenCaptureKit"))
        #expect(ideas[0].id.hasPrefix("idea:"))

        // Verify duplicate read yields same deterministic ID
        let ideasAgain = try iCloudIdeaStore.readReport(from: tempDir).events
        #expect(ideasAgain.first?.id == ideas.first?.id)
    }
}
