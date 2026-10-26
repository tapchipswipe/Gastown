import CryptoKit
import Foundation

/// Pure Swift zero-dependency wire format protobuf decoder for Time Atlas updates.
public struct ProtoWireDecoder: Sendable {
    public enum WireType: Int, Sendable {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case startGroup = 3
        case endGroup = 4
        case fixed32 = 5
    }

    public struct Field: Sendable {
        public let fieldNumber: Int
        public let wireType: WireType
        public let data: Data

        public var stringValue: String? {
            String(data: data, encoding: .utf8)
        }
    }

    public enum DecodeError: Error { case fileLimit, invalidKey, varintOverflow, truncated, unsupportedWireType, invalidLength, fieldLimit }
    public static func decodeFields(from data: Data, maximumFields: Int = 10_000) throws -> [Field] {
        var remaining = maximumFields
        return try decodeFields(from: data, remaining: &remaining)
    }
    static func decodeFields(from input: Data, remaining: inout Int) throws -> [Field] {
        let data = Data(input); var index = 0; var fields: [Field] = []
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in 0..<10 {
                guard index < data.count else { throw DecodeError.truncated }
                let byte = data[index]; index += 1
                guard shift < 9 || byte <= 1 else { throw DecodeError.varintOverflow }
                value |= UInt64(byte & 127) << (shift * 7)
                if byte & 128 == 0 { return value }
            }
            throw DecodeError.varintOverflow
        }
        while index < data.count {
            guard remaining > 0 else { throw DecodeError.fieldLimit }; remaining -= 1
            let key = try varint(), number = key >> 3
            guard number > 0, number <= 536_870_911 else { throw DecodeError.invalidKey }
            guard let wire = WireType(rawValue: Int(key & 7)), wire != .startGroup, wire != .endGroup else { throw DecodeError.unsupportedWireType }
            let value: Data
            if wire == .varint {
                var number = try varint().littleEndian
                value = withUnsafeBytes(of: &number) { Data($0) }
            } else {
                let length: UInt64
                switch wire { case .fixed32: length = 4; case .fixed64: length = 8; default: length = try varint() }
                guard length <= UInt64(data.count - index) else { throw DecodeError.invalidLength }
                let end = index + Int(length)
                value = data.subdata(in: index..<end); index = end
            }
            fields.append(Field(fieldNumber: Int(number), wireType: wire, data: value))
        }
        return fields
    }
}

public struct TimeAtlasReader: Sendable {
    public static var defaultICloudDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~com~timeatlaslabs~Pat/Documents")
    }

    public static func readReport(from directory: URL, limits: IntakeLimits = IntakeLimits()) throws -> IntakeReport {
        try BoundedIntake.load(directory, extensions: ["pb"], limits: limits) { data, url, date in
            let relative = String(url.path.dropFirst(directory.path.count))
            return try parseData(data, fallbackDate: date, filename: relative, maximumFields: limits.fields)
        }
    }

    public static func parseData(_ data: Data, fallbackDate: Date = Date(), filename: String = "", maximumFields: Int = 10_000) throws -> [HistoryEvent] {
        guard data.count <= 4 * 1024 * 1024 else { throw ProtoWireDecoder.DecodeError.fileLimit }
        var remaining = maximumFields
        let topFields = try ProtoWireDecoder.decodeFields(from: data, remaining: &remaining)
        var events: [HistoryEvent] = []

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        for (position, field) in topFields.enumerated() {
            switch field.fieldNumber {
            case 21: // DateAnalysis (Field #21 in FullDirectory)
                let subfields = try ProtoWireDecoder.decodeFields(from: field.data, remaining: &remaining)
                var dateStr = ""
                var summary = ""
                for sf in subfields {
                    if sf.fieldNumber == 2, let s = sf.stringValue, !s.isEmpty {
                        dateStr = s
                    } else if sf.fieldNumber == 4, let s = sf.stringValue, !s.isEmpty {
                        summary = s
                    }
                }
                if !dateStr.isEmpty || !summary.isEmpty {
                    let ts = dateFormatter.date(from: dateStr) ?? fallbackDate
                    let title = summary.isEmpty ? "Daily Activity" : summary.capitalized
                    let id = "timeatlas:analysis:\(dateStr):\(title.lowercased())"
                    events.append(HistoryEvent(id: id, timestamp: ts, source: "Time Atlas", title: title, detail: "Date: \(dateStr)"))
                }

            case 1: // Event (Field #1 in FullDirectory)
                let subfields = try ProtoWireDecoder.decodeFields(from: field.data, remaining: &remaining)
                var eventUUID = ""
                for sf in subfields where sf.fieldNumber == 1 {
                    // Meta field #1 contains UUID
                    let metaFields = try ProtoWireDecoder.decodeFields(from: sf.data, remaining: &remaining)
                    for mf in metaFields where mf.fieldNumber == 1 {
                        if let id = mf.stringValue, !id.isEmpty {
                            eventUUID = id
                        }
                    }
                }
                if !eventUUID.isEmpty {
                    let id = "timeatlas:event:\(eventUUID)"
                    events.append(HistoryEvent(id: id, timestamp: fallbackDate, source: "Time Atlas", title: "Mobile Event", detail: "ID: \(eventUUID)"))
                }

            case 2: // JournalEntry (Field #2 in FullDirectory)
                let subfields = try ProtoWireDecoder.decodeFields(from: field.data, remaining: &remaining)
                var journalText = ""
                var entryUUID = ""
                for sf in subfields {
                    if sf.fieldNumber == 1 {
                        let metaFields = try ProtoWireDecoder.decodeFields(from: sf.data, remaining: &remaining)
                        for mf in metaFields where mf.fieldNumber == 1 {
                            if let id = mf.stringValue { entryUUID = id }
                        }
                    } else if sf.fieldNumber == 4, let text = sf.stringValue {
                        journalText = text
                    }
                }
                if !journalText.isEmpty || !entryUUID.isEmpty {
                    let title = journalText.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
                    let safeTitle = title.isEmpty ? "Journal Entry" : String(title)
                    let canonical = subfields.map { "\($0.fieldNumber):\($0.wireType.rawValue):\($0.data.base64EncodedString())" }.sorted().joined(separator: "|")
                    let id = entryUUID.isEmpty ? "timeatlas:journal:" + SHA256.hash(data: Data("\(filename):\(position):\(canonical)".utf8)).map { String(format: "%02x", $0) }.joined() : "timeatlas:journal:\(entryUUID)"
                    events.append(HistoryEvent(id: id, timestamp: fallbackDate, source: "Time Atlas", title: safeTitle, detail: journalText))
                }

            default:
                break
            }
        }

        return events
    }
}
