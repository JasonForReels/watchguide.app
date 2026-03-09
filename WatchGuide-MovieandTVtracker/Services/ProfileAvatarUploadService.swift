import Foundation

actor ProfileAvatarUploadService {
    static let shared = ProfileAvatarUploadService()
    
    private let bucket = "profile-avatars"
    
    private var supabaseURL: String {
        ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
    }
    
    func uploadAvatar(localFileURL: URL, userId: String, accessToken: String?) async throws -> String {
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else {
            throw ProfileAvatarUploadError.notConfigured
        }
        
        let data = try Data(contentsOf: localFileURL)
        guard !data.isEmpty else {
            throw ProfileAvatarUploadError.invalidData
        }
        
        let filename = "avatar-\(UUID().uuidString).jpg"
        let objectPath = "\(userId)/\(filename)"
        
        guard let encodedPath = objectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let uploadURL = URL(string: "\(supabaseURL)/storage/v1/object/\(bucket)/\(encodedPath)") else {
            throw ProfileAvatarUploadError.invalidPath
        }
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(accessToken ?? supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.addValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.addValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ProfileAvatarUploadError.uploadFailed
        }
        
        // Public URL format for public bucket reads.
        guard let encodedPublicPath = objectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let publicURL = URL(string: "\(supabaseURL)/storage/v1/object/public/\(bucket)/\(encodedPublicPath)") else {
            throw ProfileAvatarUploadError.invalidPath
        }
        
        return publicURL.absoluteString
    }
}

enum ProfileAvatarUploadError: Error {
    case notConfigured
    case invalidData
    case invalidPath
    case uploadFailed
}

