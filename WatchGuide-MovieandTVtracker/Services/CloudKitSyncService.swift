import Foundation
import CloudKit

actor CloudKitSyncService {
    static let shared = CloudKitSyncService()
    static let containerIdentifier = "iCloud.com.JasonSmith.WatchGuide-MovieandTVtracker"

    private let container: CKContainer
    private let database: CKDatabase

    private let recordType = "UserSyncSnapshot"
    private let payloadField = "payloadAsset"
    private let updatedAtField = "updatedAt"
    private let userIdField = "userId"

    private init(container: CKContainer = CKContainer(identifier: CloudKitSyncService.containerIdentifier)) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func uploadSnapshot(data: Data, userId: String) async throws {
        try await ensureCloudKitAvailable()

        let recordID = CKRecord.ID(recordName: recordName(for: userId))
        let record = try await fetchOrCreateRecord(recordID: recordID)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudkit-sync-\(UUID().uuidString).json")
        try data.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        record[userIdField] = userId as CKRecordValue
        record[updatedAtField] = Date() as CKRecordValue
        record[payloadField] = CKAsset(fileURL: tempURL)

        _ = try await database.save(record)
    }

    func downloadSnapshot(userId: String) async throws -> Data? {
        try await ensureCloudKitAvailable()

        let recordID = CKRecord.ID(recordName: recordName(for: userId))
        do {
            let record = try await database.record(for: recordID)
            guard let asset = record[payloadField] as? CKAsset,
                  let fileURL = asset.fileURL else {
                return nil
            }
            return try Data(contentsOf: fileURL)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func fetchOrCreateRecord(recordID: CKRecord.ID) async throws -> CKRecord {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: recordType, recordID: recordID)
        }
    }

    private func ensureCloudKitAvailable() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CloudKitSyncError.accountUnavailable(status)
        }
    }

    private func recordName(for userId: String) -> String {
        let safe = userId.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        return "sync_\(safe)"
    }
}

enum CloudKitSyncError: LocalizedError {
    case accountUnavailable(CKAccountStatus)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable(let status):
            switch status {
            case .noAccount:
                return "No iCloud account is signed in on this device."
            case .restricted:
                return "iCloud access is restricted on this device."
            case .couldNotDetermine:
                return "Could not determine iCloud account status."
            case .temporarilyUnavailable:
                return "iCloud is temporarily unavailable."
            case .available:
                return nil
            @unknown default:
                return "CloudKit is unavailable."
            }
        }
    }
}
