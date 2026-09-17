import Foundation

actor CloudflareImageService {
    static let shared = CloudflareImageService()

    private var accountID: String {
        ApiKeyManager.shared.get(key: "CLOUDFLARE_ACCOUNT_ID") ?? "b91363256309bc68156bb2e194d96cbf"
    }

    private var apiToken: String {
        ApiKeyManager.shared.get(key: "CLOUDFLARE_AI_TOKEN") ?? ""
    }

    private init() {}

    func generateImage(prompt: String, model: FluxModel) async throws -> Data {
        let encodedModel = model.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model.rawValue
        let urlString = "https://api.cloudflare.com/client/v4/accounts/\(accountID)/ai/run/\(encodedModel)"
        guard let url = URL(string: urlString) else {
            throw CloudflareImageError.invalidURL
        }

        let boundary = "WatchGuideBoundary\(Int.random(in: 100000...999999))"
        var body = Data()

        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        addField("prompt", prompt)
        addField("steps", String(model.steps))
        addField("width", "1024")
        addField("height", "1024")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 180

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudflareImageError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudflareImageError.apiError(statusCode: httpResponse.statusCode, message: msg)
        }

        // Response: {"result":{"image":"<base64>"},"success":true}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let base64 = result["image"] as? String,
              let imageData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            throw CloudflareImageError.invalidResponse
        }

        return imageData
    }
}

enum CloudflareImageError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Could not decode image from response."
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        }
    }
}
