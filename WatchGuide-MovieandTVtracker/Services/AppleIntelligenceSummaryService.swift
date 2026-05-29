import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

actor AppleIntelligenceSummaryService {
    static let shared = AppleIntelligenceSummaryService()

    private init() {}

    var isAvailable: Bool {
        AppleIntelligenceCapabilityService.currentReport().isAppleIntelligenceAvailableNow
    }

    func summarizeOverview(_ text: String, title: String) async throws -> String {
        let prompt = """
        Title: \(title)

        Overview:
        \(text)
        """
        return try await summarize(
            prompt: prompt,
            instructions: """
            Summarize movie or TV overviews in 2 to 4 concise bullet points.
            Keep spoilers out.
            Preserve only the main premise, tone, and setup.
            Return plain text bullets only.
            """
        )
    }

    func summarizeReview(_ text: String, author: String, title: String) async throws -> String {
        let prompt = """
        Title: \(title)
        Reviewer: \(author)

        Review:
        \(text)
        """
        return try await summarize(
            prompt: prompt,
            instructions: """
            Summarize a single movie or TV review in 2 to 4 concise bullet points.
            Capture the reviewer's main opinion, strongest praise or criticism, and overall takeaway.
            Do not invent sentiment not present in the review.
            Return plain text bullets only.
            """
        )
    }

    private func summarize(prompt: String, instructions: String) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "" }

        #if canImport(FoundationModels)
        if #available(iOS 18.0, macOS 15.0, *), isAvailable {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: trimmedPrompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif

        throw AppleIntelligenceSummaryError.unavailable
    }
}

enum AppleIntelligenceSummaryError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Intelligence summarization is unavailable on this device."
        }
    }
}
