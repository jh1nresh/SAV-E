import Foundation

enum SaveMemoryVaultAppender {
    enum AppendError: Error {
        case invalidVaultRoot
        case invalidRecord
    }

    nonisolated static func appending<Record: Encodable>(
        _ record: Record,
        to existingData: Data?
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let recordData = try encoder.encode(record)
        guard let recordObject = try JSONSerialization.jsonObject(with: recordData) as? [String: Any] else {
            throw AppendError.invalidRecord
        }

        var records: [[String: Any]]
        if let existingData {
            let existingObject = try JSONSerialization.jsonObject(with: existingData)
            guard let existingRecords = existingObject as? [[String: Any]] else {
                throw AppendError.invalidVaultRoot
            }
            records = existingRecords
        } else {
            records = []
        }

        records.insert(recordObject, at: 0)
        return try JSONSerialization.data(
            withJSONObject: records,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}
