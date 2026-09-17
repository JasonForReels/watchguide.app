//
//  SiriIntelligenceIntents.swift
//  WatchGuide-MovieandTVtracker
//
//  Extra Siri features that only light up on Apple Intelligence-capable devices.
//
//  There is no "CoreAI" framework — the new Siri is App Intents (what Siri can
//  invoke) sitting on top of FoundationModels (the on-device model). This file
//  adds the intents that are worth exposing only when that model is actually
//  usable, and degrades to a spoken explanation everywhere else rather than
//  failing silently.
//

import Foundation

#if canImport(AppIntents)
import AppIntents
#endif

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

// MARK: - Device capability gate

/// Whether the on-device model behind the new Siri can serve a request right
/// now, and what to say when it can't.
enum SiriIntelligenceCapability {
    enum State {
        case ready
        /// Not usable — carries a sentence Siri can speak verbatim.
        case unavailable(String)

        var isReady: Bool { if case .ready = self { return true }; return false }
    }

    static var current: State {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                guard model.supportsLocale(Locale.current) else {
                    return .unavailable("Apple Intelligence doesn't support your current language yet.")
                }
                return .ready
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("This feature needs an Apple Intelligence-capable device.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Turn on Apple Intelligence in Settings, then try again.")
                case .modelNotReady:
                    return .unavailable("Apple Intelligence is still getting ready. Try again in a moment.")
                default:
                    return .unavailable("Apple Intelligence isn't available right now.")
                }
            }
        }
        return .unavailable("This feature needs iOS 18 or later with Apple Intelligence.")
        #else
        return .unavailable("This feature isn't available on this platform.")
        #endif
    }
}

#if canImport(AppIntents)

// MARK: - Ask Watch Guide
//
// "Ask Watch Guide what I should watch tonight"
//
// Answers on-device when Apple Intelligence is available, and falls back to the
// cloud Atlas stack (which is what the in-app assistant uses) otherwise — so the
// intent still works on older hardware, just without the private on-device path.

struct AskWatchGuideIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Watch Guide"
    static var description = IntentDescription(
        "Ask a question about movies and TV. Answered privately on-device when supported.",
        categoryName: "Discover"
    )

    @Parameter(title: "Question", description: "What you want to know about movies or TV.", requestValueDialog: "What would you like to know?")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Watch Guide \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "What would you like to know?")
        }

        let liked: [SavedMediaItem] = await MainActor.run {
            Array(StorageService.shared.liked.prefix(20))
        }

        var answer = ""

        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *), SiriIntelligenceCapability.current.isReady {
            answer = (try? await answerOnDevice(trimmed, liked: liked)) ?? ""
        }
        #endif

        if answer.isEmpty {
            // Cloud fallback: same service the in-app assistant uses. Siri speaks
            // the reply, so control tags have to come out of it.
            let (content, _) = try await AIService.shared.sendMessage(
                trimmed,
                conversationHistory: [],
                likedItems: liked,
                webSearchEnabled: true
            )
            answer = AIService.strippingControlTags(content)
        }

        guard !answer.isEmpty else {
            return .result(dialog: "I couldn't come up with an answer for that. Try rephrasing it.")
        }

        return .result(dialog: IntentDialog(stringLiteral: answer))
    }

    #if canImport(FoundationModels) && !os(tvOS)
    @available(iOS 18.0, macOS 15.0, *)
    private func answerOnDevice(_ question: String, liked: [SavedMediaItem]) async throws -> String {
        let taste = liked.isEmpty
            ? "The person hasn't liked anything yet."
            : "Titles this person has liked: " + liked.map(\.title).joined(separator: ", ") + "."

        let instructions = """
        You are Watch Guide's movie and TV expert, answering out loud through Siri.
        Answer in at most three short sentences of plain spoken language — no
        markdown, no lists, no links. Only mention real movies and shows. If you
        aren't sure of a fact, say so instead of guessing.

        \(taste)
        """

        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        let response = try await session.respond(to: question)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}

// MARK: - What Should I Watch Tonight
//
// A one-shot pick from the user's own watchlist, reasoned about on-device so the
// watchlist never leaves the phone. Requires Apple Intelligence — without it
// there's nothing here that "Show my watchlist" doesn't already do.

struct PickTonightsWatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Pick Something to Watch Tonight"
    static var description = IntentDescription(
        "Picks one title from your watchlist and says why, entirely on-device.",
        categoryName: "Discover"
    )

    @Parameter(title: "Mood", description: "Optional mood or occasion, like \"something light\".", default: "")
    var mood: String

    static var parameterSummary: some ParameterSummary {
        Summary("Pick something to watch tonight \(\.$mood)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if case .unavailable(let why) = SiriIntelligenceCapability.current {
            return .result(dialog: IntentDialog(stringLiteral: why))
        }

        let items: [SavedMediaItem] = await MainActor.run {
            Array(StorageService.shared.wantToWatch.prefix(25))
        }
        guard !items.isEmpty else {
            return .result(dialog: "Your watchlist is empty. Add a few titles and ask me again.")
        }

        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *) {
            let moodClause = mood.trimmingCharacters(in: .whitespacesAndNewlines)
            let instructions = """
            You pick exactly one title for someone's evening from a list they
            already want to watch. Answer in one or two spoken sentences: name the
            title, then say why it fits. Never invent a title that isn't on the list.
            """

            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let prompt = """
            Watchlist: \(items.map(\.title).joined(separator: ", ")).
            \(moodClause.isEmpty ? "" : "They're in the mood for: \(moodClause).")
            Pick one.
            """

            if let response = try? await session.respond(to: prompt) {
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return .result(dialog: IntentDialog(stringLiteral: text))
                }
            }
        }
        #endif

        // On-device model dropped out mid-request — fall back to a plain pick so
        // Siri still answers with something from the user's own list.
        let pick = items.randomElement()?.title ?? items[0].title
        return .result(dialog: "How about \(pick)? It's already on your watchlist.")
    }
}

#endif
