//
//  AtlasVoiceSession.swift
//  WatchGuide-MovieandTVtracker
//
//  Drives a real-time voice conversation with Ask Atlas using the Gemini
//  Live API (gemini-3.1-flash-live-preview). This is a fully separate path
//  from the text chat in AIService — it speaks a bidirectional WebSocket
//  protocol streaming raw PCM audio in both directions, so it shares no
//  runtime state with the chat and cannot conflict with it.
//
//  iOS-only (depends on AtlasVoiceAudioIO / AVAudioSession).
//

import Foundation
import AVFoundation
import Observation

/// The prebuilt Gemini Live speaker voices offered to the user. These eight are
/// the universally-supported (half-cascade) voices; the model can't clone a
/// custom or specific real person's voice, so this is the available palette.
enum AtlasVoice: String, CaseIterable, Identifiable {
    case charon  = "Charon"
    case puck    = "Puck"
    case kore    = "Kore"
    case fenrir  = "Fenrir"
    case aoede   = "Aoede"
    case leda    = "Leda"
    case orus    = "Orus"
    case zephyr  = "Zephyr"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Short description of the voice's character for the picker.
    var blurb: String {
        switch self {
        case .charon: return "Warm, grounded"
        case .puck:   return "Upbeat, playful"
        case .kore:   return "Clear, neutral"
        case .fenrir: return "Deep, confident"
        case .aoede:  return "Bright, friendly"
        case .leda:   return "Soft, relaxed"
        case .orus:   return "Firm, mature"
        case .zephyr: return "Light, airy"
        }
    }

    static let defaultVoice: AtlasVoice = .charon
    /// `@AppStorage` key for the user's chosen voice.
    static let storageKey = "atlas_voice_name"
}

/// Remembers whether this API key's Live socket currently accepts Grounding
/// with Google Search.
///
/// `gemini-3.1-flash-live-preview` supports grounding on the socket, but the
/// key's search-grounding allowance can run out, and the server signals that by
/// closing the connection rather than by degrading. When that happens we note
/// it here and use the out-of-band search function for a while instead of
/// re-attempting a connection we know will drop.
enum AtlasLiveGrounding {
    private static let retryAfterKey = "atlas_live_grounding_retry_after"
    /// How long to stay on the fallback before trying native grounding again.
    private static let backoff: TimeInterval = 6 * 60 * 60

    /// Whether the next session should ask for native grounding.
    static var isAvailable: Bool {
        guard let retryAfter = UserDefaults.standard.object(forKey: retryAfterKey) as? Date else {
            return true
        }
        return Date() >= retryAfter
    }

    static func markUnavailable() {
        UserDefaults.standard.set(Date().addingTimeInterval(backoff), forKey: retryAfterKey)
    }

    /// Clears the backoff — used when the user changes the API key.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: retryAfterKey)
    }
}

/// Continuous expression controls for Atlas's delivery. The API has no numeric
/// "emotion" parameters on this model, so each axis is bucketed into descriptive
/// "Director's Note" text that's composed into the system instruction at setup.
/// Values are normalized 0...1.
struct AtlasVoiceExpression {
    var energy: Double   // 0 = calm / low-key,   1 = high / excited
    var warmth: Double   // 0 = cool / neutral,   1 = warm / friendly
    var pace: Double     // 0 = slow / measured,  1 = quick / lively
    var drama: Double    // 0 = plain / matter-of-fact, 1 = cinematic / theatrical

    static let `default` = AtlasVoiceExpression(energy: 0.5, warmth: 0.6, pace: 0.5, drama: 0.3)

    /// `@AppStorage` keys for each axis (stored as separate Doubles).
    enum Key {
        static let energy = "atlas_expr_energy"
        static let warmth = "atlas_expr_warmth"
        static let pace   = "atlas_expr_pace"
        static let drama  = "atlas_expr_drama"
    }

    private enum Band { case low, mid, high }
    private func band(_ value: Double) -> Band {
        if value < 0.34 { return .low }
        if value < 0.67 { return .mid }
        return .high
    }

    /// Director's-note guidance appended to the system instruction. Only the
    /// non-neutral (low/high) axes contribute, so a balanced setting reads clean.
    var directorsNote: String {
        var notes: [String] = []

        switch band(energy) {
        case .low:  notes.append("calm, low-key energy")
        case .high: notes.append("high, genuinely excited energy (never shouty)")
        case .mid:  break
        }
        switch band(warmth) {
        case .low:  notes.append("a cool, matter-of-fact tone")
        case .high: notes.append("a warm, friendly tone")
        case .mid:  break
        }
        switch band(pace) {
        case .low:  notes.append("a slow, deliberate pace")
        case .high: notes.append("a quick, lively pace")
        case .mid:  break
        }
        switch band(drama) {
        case .low:  notes.append("a plain, understated delivery")
        case .high: notes.append("a dramatic, cinematic delivery")
        case .mid:  break
        }

        guard !notes.isEmpty else { return "" }
        return " Delivery: speak with " + listPhrase(notes) + "."
    }

    private func listPhrase(_ items: [String]) -> String {
        switch items.count {
        case 0:  return ""
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }
}

/// One-tap personality presets. Each simply moves the expression sliders to a
/// recognizable starting point; the sliders remain the source of truth.
enum AtlasVoiceStyle: String, CaseIterable, Identifiable {
    case natural
    case chill
    case hyped
    case critic
    case noir

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .natural: return "Natural"
        case .chill:   return "Chill"
        case .hyped:   return "Hyped"
        case .critic:  return "Film Critic"
        case .noir:    return "Noir Narrator"
        }
    }

    var blurb: String {
        switch self {
        case .natural: return "Balanced, conversational"
        case .chill:   return "Relaxed and easygoing"
        case .hyped:   return "High-energy and excited"
        case .critic:  return "Sharp, insightful, dry wit"
        case .noir:    return "Moody, cinematic narrator"
        }
    }

    /// Slider values this preset applies.
    var expression: AtlasVoiceExpression {
        switch self {
        case .natural: return AtlasVoiceExpression(energy: 0.5, warmth: 0.6, pace: 0.5, drama: 0.3)
        case .chill:   return AtlasVoiceExpression(energy: 0.25, warmth: 0.8, pace: 0.25, drama: 0.2)
        case .hyped:   return AtlasVoiceExpression(energy: 0.95, warmth: 0.75, pace: 0.85, drama: 0.5)
        case .critic:  return AtlasVoiceExpression(energy: 0.5, warmth: 0.35, pace: 0.45, drama: 0.4)
        case .noir:    return AtlasVoiceExpression(energy: 0.3, warmth: 0.3, pace: 0.2, drama: 0.95)
        }
    }
}

#if os(iOS)

@MainActor
@Observable
final class AtlasVoiceSession {

    // MARK: - Observable State

    enum Phase: Equatable {
        case idle
        case connecting
        case listening      // mic open, waiting for / hearing the user
        case speaking       // Atlas is talking back
        case ended(reason: EndReason)
    }

    enum EndReason: Equatable {
        case user
        case timeLimitReached
        case error(String)
    }

    private(set) var phase: Phase = .idle
    /// Live transcript of what the user is saying.
    private(set) var userTranscript: String = ""
    /// Live transcript of Atlas's spoken reply.
    private(set) var atlasTranscript: String = ""
    /// Seconds remaining in this session, or `nil` for the Unlimited tier.
    private(set) var remainingSeconds: Int?
    /// Set when the session ends because the daily/per-session budget ran out.
    private(set) var hitQuotaLimit = false
    private(set) var isMuted = false
    /// Live mic input level (0...1) for the listening animation.
    private(set) var micLevel: Float = 0

    // MARK: - Dependencies / internals

    private let model = "models/gemini-3.1-flash-live-preview"
    private let audioIO = AtlasVoiceAudioIO()
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var elapsedSeconds = 0
    private var sessionLimitSeconds: Int?
    private var didConsumeQuota = false
    /// Whether this session asked the Live model to ground with Google Search
    /// itself. Falls back to the out-of-band search function if the socket
    /// rejects grounding (see `AtlasLiveGrounding`).
    private var useNativeGrounding = true
    /// Set once we've already retried this session without native grounding, so
    /// a second failure surfaces as a real error instead of looping.
    private var didRetryWithoutGrounding = false
    /// Held so a transparent reconnect can rebuild the same setup message.
    private var sessionVoice: AtlasVoice = .defaultVoice
    private var sessionExpression: AtlasVoiceExpression = .default
    private var sessionRestrictedMode = false
    /// True once a model turn completed; the next user utterance starts a fresh
    /// exchange (so captions don't pile into one paragraph).
    private var turnFinished = false

    // MARK: - Public API

    /// Requests mic permission, opens the WebSocket, and begins the conversation.
    func start(voice: AtlasVoice, expression: AtlasVoiceExpression, restrictedMode: Bool) async {
        guard phase == .idle else { return }

        // Gate on the time-based daily budget.
        guard AtlasVoiceQuota.canStartSession() else {
            hitQuotaLimit = true
            phase = .ended(reason: .timeLimitReached)
            return
        }

        guard await requestMicPermission() else {
            phase = .ended(reason: .error("Microphone access is needed for voice mode. Enable it in Settings."))
            return
        }

        // Resolve the Gemini key exactly like the rest of the app: Keychain
        // first, then the bundled Gemini key fallback.
        let key = AtlasAIProvider.gemini.apiKey
        guard !key.isEmpty else {
            phase = .ended(reason: .error("No Gemini API key is configured for voice mode."))
            return
        }

        phase = .connecting
        sessionLimitSeconds = AtlasVoiceQuota.availableSessionSeconds()
        remainingSeconds = sessionLimitSeconds

        sessionVoice = voice
        sessionExpression = expression
        sessionRestrictedMode = restrictedMode
        useNativeGrounding = AtlasLiveGrounding.isAvailable

        openConnection(key: key)
    }

    /// Opens the socket and sends the setup message. Split out of `start` so a
    /// grounding fallback can reconnect without re-running the mic and quota
    /// gates (or double-charging the daily budget).
    private func openConnection(key: String) {
        // Standard documented Live API auth: v1beta endpoint with ?key=.
        let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(key)"
        guard let url = URL(string: endpoint) else {
            phase = .ended(reason: .error("Voice mode couldn't build the connection URL."))
            return
        }
        #if DEBUG
        print("AtlasVoice connecting: v1beta · grounding=\(useNativeGrounding ? "native" : "function") · keyPrefix=\(key.prefix(4))…")
        #endif

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        sendSetup(
            voice: sessionVoice,
            expression: sessionExpression,
            restrictedMode: sessionRestrictedMode
        )
        startReceiveLoop()
    }

    /// Ends the conversation and records the time used against the daily budget.
    func end(reason: EndReason) {
        guard !isEnded else { return }

        countdownTask?.cancel(); countdownTask = nil
        receiveTask?.cancel(); receiveTask = nil
        audioIO.stop()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        if !didConsumeQuota {
            AtlasVoiceQuota.consume(seconds: elapsedSeconds)
            didConsumeQuota = true
        }

        if case .timeLimitReached = reason { hitQuotaLimit = true }
        phase = .ended(reason: reason)
    }

    func toggleMute() {
        isMuted.toggle()
        audioIO.setMuted(isMuted)
    }

    private var isEnded: Bool {
        if case .ended = phase { return true }
        return false
    }

    // MARK: - Setup message

    // Web search is served by the Live model itself: gemini-3.1-flash-live-preview
    // supports Grounding with Google Search on the socket, so the same model
    // that's speaking does the searching — no second request, no extra latency,
    // and the search is part of its turn rather than bolted on afterwards.
    //
    // Grounding has historically closed this socket with a 1011 quota error when
    // the key's search-grounding allowance is exhausted, so the old out-of-band
    // path is kept as a fallback: on that specific failure we reconnect once
    // with the custom `search_web` function instead and note it in
    // `AtlasLiveGrounding` so the next few sessions skip the doomed attempt.
    private static let searchFunctionName = "search_web"
    private static let actionFunctionName = "app_action"

    private func sendSetup(voice: AtlasVoice, expression: AtlasVoiceExpression, restrictedMode: Bool) {
        let setupBody: [String: Any] = [
            "model": model,
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": ["voiceName": voice.rawValue]
                    ]
                ],
                // 3.1 Flash Live uses thinkingLevel (not thinkingBudget);
                // "minimal" keeps latency lowest for conversation.
                "thinkingConfig": ["thinkingLevel": "minimal"]
            ],
            "systemInstruction": [
                "parts": [["text": systemInstruction(expression: expression, restrictedMode: restrictedMode)]]
            ],
            "tools": toolsPayload(),
            "inputAudioTranscription": [:],
            "outputAudioTranscription": [:]
        ]
        sendJSON(["setup": setupBody])
    }

    /// The tool set sent in the setup message. Native Google Search grounding
    /// when it's available, the out-of-band search function when it isn't —
    /// `app_action` is present either way.
    private func toolsPayload() -> [[String: Any]] {
        let searchFunction: [String: Any] = [
            "name": Self.searchFunctionName,
            "description": "Search the web for up-to-date movie & TV facts — box office, ratings, release dates, cast, awards, or anything current. Returns a short text summary.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "What to search for, e.g. 'Dune Part Two worldwide box office'"
                    ]
                ],
                "required": ["query"]
            ]
        ]

        let actionFunction: [String: Any] = [
            "name": Self.actionFunctionName,
            "description": "Operate the WatchGuide app on the user's behalf — add or remove a title from their watchlist, mark something watched, like it, open a title or person, or move to another screen. Only call this when the user actually asks you to do it.",
            "parameters": [
                "type": "object",
                "properties": [
                    "verb": [
                        "type": "string",
                        "enum": AtlasActionVerb.allCases.map(\.rawValue),
                        "description": "Which operation to perform"
                    ],
                    "argument": [
                        "type": "string",
                        "description": "The exact official title, the person's name, or for navigate one of: browse, search, lists, watchlist, streaming, watchhour, me, settings"
                    ],
                    "type": [
                        "type": "string",
                        "enum": ["movie", "tv"],
                        "description": "For title lookups, whether it's a movie or a TV show. Omit otherwise."
                    ]
                ],
                "required": ["verb", "argument"]
            ]
        ]

        // Google Search and function declarations are separate entries in the
        // tools array — they combine, they don't nest.
        if useNativeGrounding {
            return [
                ["google_search": [String: Any]()],
                ["functionDeclarations": [actionFunction]]
            ]
        }
        return [["functionDeclarations": [searchFunction, actionFunction]]]
    }

    private func systemInstruction(expression: AtlasVoiceExpression, restrictedMode: Bool) -> String {
        let persona = AtlasPersona.current
        var prompt = """
        You are Atlas, a movie & TV voice companion inside the WatchGuide app. \
        You are speaking out loud, so reply in short, natural, conversational sentences — \
        no markdown, no bullet points, no emoji, no special tags or symbols. \
        Keep answers brief and to the point. \
        For recommendations, suggest one or two titles at a time and say why, then ask if they want more. \
        Spell out titles naturally; never read out punctuation or formatting.

        \(persona.voiceCharacterPrompt)
        """
        prompt += AtlasPersona.addressPrompt
        prompt += " You can operate the app by calling the app_action function — adding to the " +
            "watchlist, marking things watched, opening a title, or moving to another screen. " +
            "Only call it when the user actually asks you to do something, never for a suggestion " +
            "they haven't accepted, and say what you did in one short sentence afterwards."
        prompt += AtlasMemoryStore.shared.promptBlock
        prompt += AtlasProactiveEngine.shared.promptContext
        if useNativeGrounding {
            prompt += " You have Google Search built in. When the user asks about box office, ratings, " +
                "release dates, what's new, or any current or factual detail you're not certain of, " +
                "search before answering instead of guessing — then answer in one or two spoken " +
                "sentences. Don't mention the search itself or read out sources."
        } else {
            prompt += " When the user asks about box office, ratings, release dates, what's new, or any " +
                "current or factual detail you're not certain of, call the search_web function instead of " +
                "guessing — then answer in one or two spoken sentences using the result. Don't mention the search itself."
        }
        prompt += " Never repeat rumours, leaks, insider claims, or speculation, even if a search result " +
            "contains them — not even to describe or debunk them. Only say what has been officially " +
            "announced or released. If something isn't confirmed, say there's no official announcement yet " +
            "and leave it there. Never guess at future casting, plots, renewals, or release dates."
        // Personality / delivery direction chosen by the user (expression sliders).
        prompt += expression.directorsNote
        prompt += ContentFilterService.shared.alwaysOnSafetyPrompt
        if restrictedMode {
            prompt += ContentFilterService.shared.kidsModeSystemPrompt
        }
        return prompt
    }

    // MARK: - Sending

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(string)) { _ in }
    }

    // MARK: - Receiving

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while let self, await !self.isEnded {
                guard let task = await self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    await self.handle(message: message)
                } catch {
                    await self.handleConnectionDrop(error: error)
                    break
                }
            }
        }
    }

    /// Turns a dropped/rejected WebSocket into a useful message. Ignored if the
    /// drop is just our own end() cancelling the receive task.
    private func handleConnectionDrop(error: Error) {
        guard !isEnded else { return }

        // Grounding quota exhausted: retry once on the out-of-band search
        // function rather than dumping the user out of the conversation.
        if useNativeGrounding, !didRetryWithoutGrounding, isGroundingRejection(error: error) {
            didRetryWithoutGrounding = true
            useNativeGrounding = false
            AtlasLiveGrounding.markUnavailable()
            reconnectWithoutGrounding()
            return
        }

        var detail: [String] = []
        if let task = webSocketTask {
            if task.closeCode != .invalid { detail.append("close=\(task.closeCode.rawValue)") }
            if let reasonData = task.closeReason,
               let reason = String(data: reasonData, encoding: .utf8), !reason.isEmpty {
                detail.append(reason)
            }
        }
        let ns = error as NSError
        detail.append("\(ns.domain)#\(ns.code)")
        let detailText = detail.joined(separator: " · ")
        #if DEBUG
        print("⚠️ AtlasVoice connection dropped — \(detailText) :: \(error.localizedDescription)")
        #endif

        // Surface the real reason on screen so it's diagnosable without the console.
        end(reason: .error("Couldn't reach the voice service.\n(\(detailText))"))
    }

    /// Whether a socket close looks like the server refusing grounding rather
    /// than a network problem. The Live API reports it as an internal-error
    /// close (1011) whose reason mentions the exhausted quota.
    private func isGroundingRejection(error: Error) -> Bool {
        var text = (error as NSError).localizedDescription.lowercased()
        var isInternalErrorClose = false
        if let task = webSocketTask {
            isInternalErrorClose = task.closeCode == .internalServerError
            if let reasonData = task.closeReason,
               let reason = String(data: reasonData, encoding: .utf8) {
                text += " " + reason.lowercased()
            }
        }

        let namesTheCause = ["quota", "grounding", "exhausted", "resource_exhausted", "rate limit"]
            .contains { text.contains($0) }
        if namesTheCause { return true }

        // A bare 1011 with no reason, before the conversation ever started, is
        // the server rejecting the setup message — grounding is the only part
        // of that message that can be refused per-key.
        return isInternalErrorClose && phase == .connecting
    }

    /// Tears down just the socket and dials again with the fallback tool set.
    /// The countdown and elapsed time carry over, so the reconnect costs the
    /// user nothing and doesn't re-charge their daily budget.
    private func reconnectWithoutGrounding() {
        #if DEBUG
        print("AtlasVoice: grounding refused — reconnecting with the search function")
        #endif
        receiveTask?.cancel(); receiveTask = nil
        audioIO.stop()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        let key = AtlasAIProvider.gemini.apiKey
        guard !key.isEmpty else {
            end(reason: .error("Couldn't reach the voice service."))
            return
        }
        phase = .connecting
        openConnection(key: key)
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d):           data = d
        case .string(let s):         data = Data(s.utf8)
        @unknown default:            return
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if root["setupComplete"] != nil {
            beginConversation()
            return
        }

        if let goAway = root["goAway"], !(goAway is NSNull) {
            end(reason: .user)
            return
        }

        // The model is asking us to run a function (web search).
        if let toolCall = root["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]] {
            handleToolCalls(calls)
            return
        }

        guard let serverContent = root["serverContent"] as? [String: Any] else { return }

        if serverContent["interrupted"] as? Bool == true {
            audioIO.flushPlayback()
        }

        if let input = serverContent["inputTranscription"] as? [String: Any],
           let text = input["text"] as? String, !text.isEmpty {
            // A new user utterance after a completed turn starts a fresh
            // exchange — clear the previous question and answer.
            if turnFinished {
                userTranscript = ""
                atlasTranscript = ""
                turnFinished = false
            }
            userTranscript += text
        }

        if let output = serverContent["outputTranscription"] as? [String: Any],
           let text = output["text"] as? String {
            atlasTranscript += text
        }

        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            phase = .speaking
            for part in parts {
                if let inlineData = part["inlineData"] as? [String: Any],
                   let b64 = inlineData["data"] as? String,
                   let audio = Data(base64Encoded: b64) {
                    audioIO.enqueuePlayback(pcm16Data: audio)
                }
            }
        }

        if serverContent["turnComplete"] as? Bool == true {
            // Keep this exchange's captions on screen; they're cleared when the
            // user's next utterance arrives.
            phase = .listening
            turnFinished = true
        }
    }

    // MARK: - Function calling (web search)

    /// Runs each requested function call and streams the results back. The model
    /// resumes speaking once it receives the toolResponse.
    private func handleToolCalls(_ calls: [[String: Any]]) {
        Task { [weak self] in
            guard let self else { return }
            var responses: [[String: Any]] = []
            for call in calls {
                let name = call["name"] as? String ?? ""
                let id = call["id"] as? String
                let args = call["args"] as? [String: Any] ?? [:]

                var resultText = "No results found."
                if name == Self.searchFunctionName, let query = args["query"] as? String, !query.isEmpty {
                    resultText = await AtlasVoiceSession.searchViaGemini(query: query)
                } else if name == Self.actionFunctionName {
                    resultText = await AtlasVoiceSession.runAppAction(args: args)
                }

                var response: [String: Any] = [
                    "name": name,
                    "response": ["result": resultText]
                ]
                if let id { response["id"] = id }
                responses.append(response)
            }
            await self.sendToolResponse(responses)
        }
    }

    private func sendToolResponse(_ responses: [[String: Any]]) {
        guard !isEnded else { return }
        sendJSON(["toolResponse": ["functionResponses": responses]])
    }

    /// Bridges an `app_action` function call to `AtlasActionCenter` and reports
    /// back what actually happened, so the model can't narrate an action that
    /// silently failed.
    private static func runAppAction(args: [String: Any]) async -> String {
        guard let rawVerb = args["verb"] as? String,
              let verb = AtlasActionVerb(rawValue: rawVerb.lowercased()),
              let argument = (args["argument"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !argument.isEmpty else {
            return "That action wasn't understood, so nothing was changed."
        }

        let preferredType = (args["type"] as? String).flatMap { MediaType(rawValue: $0.lowercased()) }
        let action = AtlasAction(verb: verb, argument: argument, preferredType: preferredType)

        let receipts = await AtlasActionCenter.shared.execute([action])
        guard let receipt = receipts.first else {
            return "App actions are switched off in Settings, so nothing was changed."
        }
        return receipt.succeeded ? "Done: \(receipt.summary)." : "Failed: \(receipt.summary)."
    }

    /// One-shot grounded web search via Gemini's REST endpoint with Google Search.
    /// Only reached in fallback mode — normally the Live model grounds its own
    /// answers on the socket. This stays on a standard (non-Live) model because
    /// Live preview models are bidi-only and don't serve `generateContent`.
    /// Returns a short text summary suitable for the model to read aloud.
    /// `nonisolated` static so it can run off the main actor.
    private nonisolated static func searchViaGemini(query: String) async -> String {
        let key = AtlasAIProvider.gemini.apiKey
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        guard !key.isEmpty, let url = URL(string: endpoint) else {
            return "Search is unavailable right now."
        }

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": "You are a concise movie/TV research assistant. Use web search. Answer in 1-2 short, spoken-friendly sentences with exact figures and dates. No markdown, no URLs, no preamble."]]
            ],
            "contents": [["role": "user", "parts": [["text": query]]]],
            "tools": [["google_search": [String: Any]()]],
            "generationConfig": ["maxOutputTokens": 400, "temperature": 0.3]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = root["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
        } catch {
            #if DEBUG
            print("AtlasVoice Gemini search failed: \(error.localizedDescription)")
            #endif
        }
        return "I couldn't find that right now."
    }

    // MARK: - Conversation start (after setupComplete)

    private func beginConversation() {
        do {
            let task = webSocketTask
            try audioIO.start(onMicChunk: { data in
                // Runs on the audio thread; URLSessionWebSocketTask.send is
                // safe to call off the main actor.
                let b64 = data.base64EncodedString()
                let json = "{\"realtimeInput\":{\"audio\":{\"data\":\"\(b64)\",\"mimeType\":\"audio/pcm;rate=16000\"}}}"
                task?.send(.string(json)) { _ in }
            }, onMicLevel: { [weak self] level in
                Task { @MainActor in self?.micLevel = level }
            })
        } catch {
            end(reason: .error("Couldn't start the microphone."))
            return
        }
        phase = .listening
        // A reconnect reuses the countdown already running for this session.
        if countdownTask == nil { startCountdown() }
    }

    private func startCountdown() {
        let limit = sessionLimitSeconds
        countdownTask = Task { [weak self] in
            while let self, await !self.isEnded {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.tickCountdown(limit: limit)
            }
        }
    }

    private func tickCountdown(limit: Int?) {
        guard !isEnded else { return }
        elapsedSeconds += 1
        guard let limit else { return }   // Unlimited tier: no enforcement.
        let remaining = max(0, limit - elapsedSeconds)
        remainingSeconds = remaining
        if remaining == 0 {
            end(reason: .timeLimitReached)
        }
    }

    // MARK: - Permission

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

#endif
