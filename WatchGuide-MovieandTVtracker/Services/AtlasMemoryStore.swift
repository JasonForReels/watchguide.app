//
//  AtlasMemoryStore.swift
//  WatchGuide-MovieandTVtracker
//
//  Long-term memory for Atlas. Everything here is stored locally in the app's
//  Documents directory — memories are never uploaded, and the user can read,
//  delete, or wipe them from Settings.
//
//  Atlas writes memories by emitting a [REMEMBER:kind|text] control tag, which
//  is stripped from the visible reply the same way [TRAILER:] and [PLAYLIST:]
//  already are.
//

import Foundation
import Combine

@MainActor
final class AtlasMemoryStore: ObservableObject {
    static let shared = AtlasMemoryStore()

    /// What a memory is about. Kinds are shown as sections in Settings and let
    /// us evict the least useful class of memory first when we hit the cap.
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case taste      // "loves slow-burn sci-fi", "won't watch horror"
        case personal   // "watches with their partner on Fridays"
        case context    // "halfway through Severance season 2"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .taste:    return "Taste"
            case .personal: return "About you"
            case .context:  return "Right now"
            }
        }

        var sfSymbol: String {
            switch self {
            case .taste:    return "heart.text.square"
            case .personal: return "person.text.rectangle"
            case .context:  return "clock.arrow.circlepath"
            }
        }
    }

    struct Memory: Codable, Identifiable, Hashable {
        let id: String
        let kind: Kind
        var text: String
        let createdAt: Date
        var lastUsedAt: Date

        init(kind: Kind, text: String) {
            self.id = UUID().uuidString
            self.kind = kind
            self.text = text
            self.createdAt = Date()
            self.lastUsedAt = Date()
        }
    }

    /// Hard cap on stored memories. Past this we drop the least recently used
    /// so the prompt block can never grow without bound.
    private static let capacity = 60
    /// Only the most recent slice is injected into any single prompt.
    private static let promptLimit = 24

    @Published private(set) var memories: [Memory] = []

    /// User-facing kill switch. When off, nothing is written and nothing is
    /// injected into prompts — existing memories are kept but ignored.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    static let enabledKey = "atlas_memory_enabled"

    private let fileURL: URL

    private init() {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("atlas_memory.json")

        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }

        load()
    }

    // MARK: - Reading

    /// Memories rendered for injection into a system prompt, most recent first.
    /// Empty string when memory is off or nothing has been learned yet.
    var promptBlock: String {
        guard isEnabled, !memories.isEmpty else { return "" }

        let recent = memories
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .prefix(Self.promptLimit)

        var lines: [String] = []
        for kind in Kind.allCases {
            let forKind = recent.filter { $0.kind == kind }
            guard !forKind.isEmpty else { continue }
            lines.append("\(kind.displayName):")
            lines.append(contentsOf: forKind.map { "  - \($0.text)" })
        }
        guard !lines.isEmpty else { return "" }

        return """


        WHAT YOU REMEMBER ABOUT THIS PERSON (from earlier conversations — treat as \
        background you already know, don't recite it back or announce that you remember):
        \(lines.joined(separator: "\n"))
        """
    }

    func memories(of kind: Kind) -> [Memory] {
        memories.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Writing

    /// Stores a memory, ignoring near-duplicates of something already known.
    func remember(_ text: String, kind: Kind) {
        guard isEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.count <= 240 else { return }

        let key = Self.normalized(trimmed)
        if let existingIndex = memories.firstIndex(where: { Self.normalized($0.text) == key }) {
            // Already known — refresh recency instead of storing it twice.
            memories[existingIndex].lastUsedAt = Date()
            save()
            return
        }

        memories.append(Memory(kind: kind, text: trimmed))
        evictIfNeeded()
        save()
    }

    func forget(id: String) {
        memories.removeAll { $0.id == id }
        save()
    }

    func forgetAll() {
        memories.removeAll()
        save()
    }

    /// Marks the injected memories as used so the LRU eviction keeps the ones
    /// that actually reach the model. Called once per Atlas request.
    func touchInjected() {
        guard isEnabled, !memories.isEmpty else { return }
        let injectedIDs = Set(
            memories.sorted { $0.lastUsedAt > $1.lastUsedAt }
                .prefix(Self.promptLimit)
                .map(\.id)
        )
        let now = Date()
        for index in memories.indices where injectedIDs.contains(memories[index].id) {
            memories[index].lastUsedAt = now
        }
        save()
    }

    private func evictIfNeeded() {
        guard memories.count > Self.capacity else { return }
        memories.sort { $0.lastUsedAt > $1.lastUsedAt }
        memories = Array(memories.prefix(Self.capacity))
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            memories = try JSONDecoder().decode([Memory].self, from: data)
        } catch {
            print("Error loading atlas_memory.json: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(memories)
            try data.write(to: fileURL)
        } catch {
            print("Error saving atlas_memory.json: \(error)")
        }
    }

    // MARK: - Control tag

    /// Instruction block telling the model how (and when) to write memories.
    nonisolated static var promptInstructions: String {
        """

        - MEMORY: When the user tells you something durable about themselves or their taste that would \
        make you more useful next time, end your reply with [REMEMBER:kind|fact] where kind is one of \
        taste, personal, or context. Write the fact in the third person, under 20 words \
        (e.g. [REMEMBER:taste|Dislikes jump-scare horror but likes psychological thrillers]). \
        At most one per reply, and only for things worth keeping — never for one-off questions, \
        never for anything sensitive (health, finances, relationships in distress, identity), and \
        never announce that you saved it. Do not explain or mention the tag.
        """

        }

    /// Parses `[REMEMBER:kind|text]` tags out of a reply, returning the cleaned
    /// text and the parsed memories. Mirrors `AIService.extractTrailerTags`.
    nonisolated static func extractMemoryTags(from text: String) -> (cleanedText: String, memories: [(kind: Kind, text: String)]) {
        var cleaned = text
        var found: [(kind: Kind, text: String)] = []

        let pattern = "\\[REMEMBER:([^\\]]+)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                guard let innerRange = Range(match.range(at: 1), in: cleaned),
                      let fullRange = Range(match.range, in: cleaned) else { continue }

                let inner = String(cleaned[innerRange])
                let parts = inner.components(separatedBy: "|")
                let rawKind = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                let body = parts.dropFirst().joined(separator: "|")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !body.isEmpty {
                    found.insert((Kind(rawValue: rawKind) ?? .context, body), at: 0)
                }
                cleaned.replaceSubrange(fullRange, with: "")
            }
        }

        cleaned = cleaned
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleaned, found)
    }
}
