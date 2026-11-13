#if SAVVY_CITY_MVP
import Foundation
import Combine

/// An unfinished local clue, never a confirmed place. This file belongs only
/// to the prototype's Documents container, not the production app group.
@MainActor
final class CityMVPCaptureDraftStore: ObservableObject {
    enum Failure: Equatable {
        case unreadable, oversized, writeFailed

        func message(english: Bool) -> String {
            switch self {
            case .unreadable:
                return english
                    ? "The stored draft could not be read. It has not been changed. A new draft will replace it."
                    : "無法讀取已存草稿，原檔尚未變更。輸入新草稿後將取代它。"
            case .oversized:
                return english
                    ? "This draft is too long to store. Shorten it before closing the app; the previous stored draft is unchanged."
                    : "草稿太長，無法儲存。關閉 App 前請縮短內容；原本已存的草稿尚未變更。"
            case .writeFailed:
                return english
                    ? "The draft change could not be stored. Keep this app open and try editing again."
                    : "無法儲存這次草稿變更。請保持 App 開啟，稍後再編輯重試。"
            }
        }
    }
    private nonisolated struct Payload: Codable {
        let version: Int
        let text: String
    }
    static let maximumBytes = 64 * 1_024
    @Published private(set) var text = ""
    @Published private(set) var failure: Failure?
    let fileURL: URL?
    private var unreadableFile = false
    private let isCurrentSession: () -> Bool

    init(documentsDirectory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
         storageID: String? = nil, isCurrentSession: @escaping () -> Bool = { true }) {
        self.isCurrentSession = isCurrentSession
        guard let documentsDirectory else { fileURL = nil; failure = .unreadable; return }
        var directory = documentsDirectory.appendingPathComponent("SavvyCityMVP", isDirectory: true)
            .appendingPathComponent("Capture", isDirectory: true)
        if let storageID {
            // Test namespaces cannot escape the prototype directory or share its ordinary draft.
            guard !storageID.isEmpty, storageID.utf8.count <= 100,
                  storageID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) })
            else { fileURL = nil; failure = .unreadable; return }
            directory.appendPathComponent("test-" + storageID, isDirectory: true)
        }
        fileURL = directory.appendingPathComponent("capture-draft-v1.json")
        load()
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize,
                  size <= Self.maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            guard data.count <= Self.maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            text = payload.text
        } catch {
            unreadableFile = true
            failure = .unreadable
        }
    }

    /// Synchronous atomic writes make the latest edit durable before returning.
    /// Failure preserves the current in-memory edit and the previous disk file.
    @discardableResult
    func update(_ value: String) -> Bool {
        guard isCurrentSession() else { return false }
        text = value
        guard let fileURL else { failure = .writeFailed; return false }
        do {
            if value.isEmpty {
                // An empty initial binding is not consent to erase an unreadable file.
                guard !unreadableFile else { failure = .unreadable; return false }
                if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
            } else {
                guard value.utf8.count <= Self.maximumBytes else { failure = .oversized; return false }
                let data = try JSONEncoder().encode(Payload(version: 1, text: value))
                guard data.count <= Self.maximumBytes else { failure = .oversized; return false }
                var directory = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete])
                var metadata = URLResourceValues(); metadata.isExcludedFromBackup = true
                try directory.setResourceValues(metadata)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                unreadableFile = false
            }
            failure = nil
            return true
        } catch {
            failure = .writeFailed
            return false
        }
    }

    func dismissFailure() { failure = nil }
}
#endif
