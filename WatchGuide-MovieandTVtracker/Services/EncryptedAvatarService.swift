import Foundation
import CryptoKit
import Security

actor EncryptedAvatarService {
    static let shared = EncryptedAvatarService()
    
    private let scheme = "e2ee-avatar://"
    private let bucket = "profile-avatars-e2ee"
    private var dataCache: [String: Data] = [:]
    
    private var supabaseURL: String {
        ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
    }
    
    func isEncryptedReference(_ value: String) -> Bool {
        value.hasPrefix(scheme)
    }
    
    func encryptAndUpload(localFileURL: URL, userId: String, profileId: String, accessToken: String?) async throws -> String {
        let data = try Data(contentsOf: localFileURL)
        guard !data.isEmpty else { throw EncryptedAvatarError.invalidData }
        
        let key = try fetchOrCreateKey(userId: userId)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw EncryptedAvatarError.encryptionFailed
        }
        
        let objectPath = "\(userId)/\(profileId)/\(UUID().uuidString).bin"
        try await uploadEncryptedBlob(combined, objectPath: objectPath, accessToken: accessToken)
        return "\(scheme)\(objectPath)"
    }
    
    func decryptAvatarReference(_ reference: String, userId: String, accessToken: String?) async throws -> Data {
        guard let objectPath = parseObjectPath(reference) else {
            throw EncryptedAvatarError.invalidReference
        }
        
        if let cached = dataCache[reference] {
            return cached
        }
        
        let encrypted = try await downloadEncryptedBlob(objectPath: objectPath, accessToken: accessToken)
        let key = try fetchOrCreateKey(userId: userId)
        let sealed = try AES.GCM.SealedBox(combined: encrypted)
        let decrypted = try AES.GCM.open(sealed, using: key)
        dataCache[reference] = decrypted
        return decrypted
    }
    
    private func parseObjectPath(_ reference: String) -> String? {
        guard reference.hasPrefix(scheme) else { return nil }
        let start = reference.index(reference.startIndex, offsetBy: scheme.count)
        let path = String(reference[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
    
    private func uploadEncryptedBlob(_ data: Data, objectPath: String, accessToken: String?) async throws {
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else {
            throw EncryptedAvatarError.notConfigured
        }
        guard let encodedPath = objectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(supabaseURL)/storage/v1/object/\(bucket)/\(encodedPath)") else {
            throw EncryptedAvatarError.invalidReference
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(accessToken ?? supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.addValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw EncryptedAvatarError.uploadFailed
        }
    }
    
    private func downloadEncryptedBlob(objectPath: String, accessToken: String?) async throws -> Data {
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else {
            throw EncryptedAvatarError.notConfigured
        }
        guard let encodedPath = objectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(supabaseURL)/storage/v1/object/\(bucket)/\(encodedPath)") else {
            throw EncryptedAvatarError.invalidReference
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(accessToken ?? supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw EncryptedAvatarError.downloadFailed
        }
        return data
    }
    
    private func fetchOrCreateKey(userId: String) throws -> SymmetricKey {
        let service = "watchguide.avatar.e2ee"
        let account = userId
        
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        
        query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable: kCFBooleanTrue as Any
        ]
        
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw EncryptedAvatarError.keychainFailed
        }
        
        if addStatus == errSecDuplicateItem {
            var existing: CFTypeRef?
            let duplicateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecReturnData: true,
                kSecAttrSynchronizable: kSecAttrSynchronizableAny
            ]
            let dupStatus = SecItemCopyMatching(duplicateQuery as CFDictionary, &existing)
            if dupStatus == errSecSuccess, let data = existing as? Data {
                return SymmetricKey(data: data)
            }
        }
        
        return key
    }
}

enum EncryptedAvatarError: Error {
    case notConfigured
    case invalidData
    case invalidReference
    case encryptionFailed
    case uploadFailed
    case downloadFailed
    case keychainFailed
}
