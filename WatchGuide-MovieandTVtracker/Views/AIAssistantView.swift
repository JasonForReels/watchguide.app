//
//  AIAssistantView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

// MARK: - Extracted Link Model
struct ExtractedLink: Identifiable {
    let id = UUID()
    let displayName: String
    let url: URL
}

// MARK: - Link Extraction Utility
private func extractLinks(from text: String) -> (cleanedText: String, links: [ExtractedLink]) {
    var links: [ExtractedLink] = []
    var cleaned = text
    
    // Match markdown links [text](url)
    let markdownPattern = "\\[([^\\]]+)\\]\\((https?://[^\\)]+)\\)"
    if let markdownRegex = try? NSRegularExpression(pattern: markdownPattern, options: []) {
        let matches = markdownRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
        // Process in reverse so ranges stay valid
        for match in matches.reversed() {
            if let textRange = Range(match.range(at: 1), in: cleaned),
               let urlRange = Range(match.range(at: 2), in: cleaned),
               let fullRange = Range(match.range, in: cleaned),
               let url = URL(string: String(cleaned[urlRange])) {
                let displayText = String(cleaned[textRange])
                links.insert(ExtractedLink(displayName: displayText, url: url), at: 0)
                cleaned.replaceSubrange(fullRange, with: displayText)
            }
        }
    }
    
    // Match bare URLs
    let urlPattern = "https?://[^\\s\\)\\]>\"',]+"
    if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) {
        let matches = urlRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
        for match in matches.reversed() {
            if let range = Range(match.range, in: cleaned) {
                let urlString = String(cleaned[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)"))
                if let url = URL(string: urlString) {
                    let host = url.host ?? urlString
                    let displayName = host
                        .replacingOccurrences(of: "www.", with: "")
                        .components(separatedBy: ".").first?.capitalized ?? host
                    // Only add if not already captured from markdown links
                    if !links.contains(where: { $0.url.absoluteString == url.absoluteString }) {
                        links.insert(ExtractedLink(displayName: displayName, url: url), at: 0)
                    }
                    cleaned.replaceSubrange(range, with: "")
                }
            }
        }
    }
    
    // Clean up extra whitespace/newlines left by removal
    cleaned = cleaned
        .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Deduplicate links by URL
    var seen = Set<String>()
    links = links.filter { link in
        let key = link.url.absoluteString
        if seen.contains(key) { return false }
        seen.insert(key)
        return true
    }
    
    return (cleaned, links)
}

private func domainDisplayName(from url: URL) -> String {
    let host = url.host ?? url.absoluteString
    let cleaned = host.replacingOccurrences(of: "www.", with: "")
    // Capitalize first component nicely
    let parts = cleaned.components(separatedBy: ".")
    if let first = parts.first {
        // Known site names
        let knownNames: [String: String] = [
            "boxofficemojo": "Box Office Mojo",
            "rottentomatoes": "Rotten Tomatoes",
            "imdb": "IMDb",
            "wikipedia": "Wikipedia",
            "themoviedb": "TMDB",
            "metacritic": "Metacritic",
            "variety": "Variety",
            "deadline": "Deadline",
            "hollywoodreporter": "Hollywood Reporter",
            "theguardian": "The Guardian",
            "nytimes": "NY Times",
            "bbc": "BBC",
            "reddit": "Reddit",
            "youtube": "YouTube",
            "twitter": "Twitter",
            "letterboxd": "Letterboxd",
            "the-numbers": "The Numbers",
            "forbes": "Forbes",
            "screenrant": "Screen Rant",
            "collider": "Collider",
            "indiewire": "IndieWire"
        ]
        if let known = knownNames[first.lowercased()] {
            return known
        }
        return first.prefix(1).uppercased() + first.dropFirst()
    }
    return cleaned
}

// MARK: - Top-level shell (owns the StateObject, body is trivially cheap)
struct AIAssistantView: View {
    @StateObject private var viewModel = AIAssistantViewModel()
    
    var body: some View {
        NavigationStack {
            AIAssistantBody(viewModel: viewModel)
                .navigationTitle("Scout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ClearButton(viewModel: viewModel)
                    }
                }
        }
    }
}

// MARK: - Body (layout only — no observation, just passes references)
private struct AIAssistantBody: View {
    let viewModel: AIAssistantViewModel
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            AIMessageListView(viewModel: viewModel,
                              dismissKeyboard: { isInputFocused = false })
            
            Divider()
            
            AIInputBarContainer(
                inputState: viewModel.inputState,
                isInputFocused: $isInputFocused,
                onSend: {
                    Task { await viewModel.sendMessage() }
                }
            )
        }
    }
}

/// Isolated clear-button — observes only messageCount to avoid full re-render
private struct ClearButton: View {
    @ObservedObject var viewModel: AIAssistantViewModel
    
    var body: some View {
        Button {
            viewModel.clearMessages()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.subheadline)
        }
        .disabled(viewModel.messageCount == 0)
    }
}

// MARK: - Input Bar Container (observes only the lightweight AIInputState)
private struct AIInputBarContainer: View {
    @ObservedObject var inputState: AIInputState
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    
    var body: some View {
        AIInputBar(
            inputText: $inputState.inputText,
            selectedModel: $inputState.selectedModel,
            isLoading: inputState.isLoading,
            isInputFocused: isInputFocused,
            onSend: onSend
        )
    }
}

// MARK: - Message List (observes ViewModel for structural changes only)
private struct AIMessageListView: View {
    @ObservedObject var viewModel: AIAssistantViewModel
    let dismissKeyboard: () -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if viewModel.messageCount == 0 {
                        WelcomeView(onSuggestion: { text in
                            viewModel.inputState.inputText = text
                            Task { await viewModel.sendMessage() }
                        })
                    }
                    
                    ForEach(viewModel.messages) { message in
                        let isStreaming = viewModel.streamingMessageId == message.id
                        let trailer = viewModel.trailerMessages[message.id]
                        MessageBubbleWrapper(
                            message: message,
                            trailerKey: trailer?.trailerKey,
                            trailerTitle: trailer?.trailerTitle,
                            isStreaming: isStreaming
                        )
                        .id(message.id)
                    }
                    
                    if viewModel.isThinking {
                        ThinkingBubble(thinkingText: viewModel.currentThinkingText, userQuery: viewModel.currentUserQuery)
                            .id("thinking")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.scrollTrigger) { _, _ in
                if let streamId = viewModel.streamingMessageId {
                    proxy.scrollTo(streamId, anchor: .bottom)
                } else if viewModel.isThinking {
                    proxy.scrollTo("thinking", anchor: .bottom)
                } else if let lastId = viewModel.messages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onChanged { _ in dismissKeyboard() }
            )
        }
    }
}

// MARK: - Word boundary helper
/// Returns indices into the original string where each "word" (whitespace-delimited token) ends.
/// E.g. for "Hello world\nFoo" → [5, 11, 15] meaning after char 5 you've revealed "Hello", etc.
private func wordEndIndices(in text: String) -> [String.Index] {
    var indices: [String.Index] = []
    var i = text.startIndex
    while i < text.endIndex {
        // Skip whitespace / newlines (they get included with previous word)
        if text[i].isWhitespace || text[i].isNewline {
            i = text.index(after: i)
            continue
        }
        // Walk to end of word
        while i < text.endIndex && !text[i].isWhitespace && !text[i].isNewline {
            i = text.index(after: i)
        }
        // Include trailing whitespace/newlines with this word
        while i < text.endIndex && (text[i].isWhitespace || text[i].isNewline) {
            i = text.index(after: i)
        }
        indices.append(i)
    }
    return indices
}

// MARK: - MessageBubbleWrapper (caches markdown + links, only recomputes when content length changes)
private struct MessageBubbleWrapper: View {
    let message: AIService.ChatMessage
    var trailerKey: String?
    var trailerTitle: String?
    var isStreaming: Bool
    
    @State private var cachedMarkdown: AttributedString?
    @State private var cachedLinks: [ExtractedLink] = []
    @State private var lastParsedLength: Int = -1
    
    // Word-by-word streaming state
    @State private var displayedWordCount: Int = 0
    @State private var wordRevealTimer: Timer?
    @State private var totalWordCount: Int = 0
    @State private var cleanedFullText: String = ""
    @State private var wordBoundaries: [String.Index] = []
    
    var body: some View {
        let (md, links, streamMd) = currentContent
        MessageBubble(
            message: message,
            parsedMarkdown: isStreaming ? streamMd : md,
            links: links,
            trailerKey: trailerKey,
            trailerTitle: trailerTitle,
            isStreaming: isStreaming
        )
        .onChange(of: message.content.count) { _, _ in
            if isStreaming {
                updateWordReveal()
            }
        }
        .onChange(of: isStreaming) { _, newValue in
            if !newValue {
                // Streaming ended — immediately show all content, stop timer
                wordRevealTimer?.invalidate()
                wordRevealTimer = nil
                displayedWordCount = 0
                totalWordCount = 0
                cleanedFullText = ""
                wordBoundaries = []
            }
        }
        .onDisappear {
            wordRevealTimer?.invalidate()
            wordRevealTimer = nil
        }
    }
    
    private func updateWordReveal() {
        let cleaned = cleanAIResponse(message.content)
        cleanedFullText = cleaned
        let boundaries = wordEndIndices(in: cleaned)
        wordBoundaries = boundaries
        totalWordCount = boundaries.count
        
        // If displayed count is already caught up, wait for more
        if displayedWordCount >= totalWordCount { return }
        
        // If timer is already running, it will catch up naturally
        guard wordRevealTimer == nil else { return }
        
        // Start a timer to reveal words one by one
        wordRevealTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { timer in
            DispatchQueue.main.async {
                if displayedWordCount < totalWordCount {
                    displayedWordCount += 1
                } else {
                    // Caught up — pause the timer until more content arrives
                    timer.invalidate()
                    wordRevealTimer = nil
                }
            }
        }
    }
    
    private var currentContent: (AttributedString, [ExtractedLink], AttributedString) {
        if message.role == "user" { return (AttributedString(), [], AttributedString()) }
        
        // Full parsed content (for non-streaming / final display)
        let len = message.content.count
        var fullMd: AttributedString
        var links: [ExtractedLink]
        
        if len == lastParsedLength, let cached = cachedMarkdown {
            fullMd = cached
            links = cachedLinks
        } else {
            let extraction = extractLinks(from: message.content)
            let parsed = parseMarkdown(extraction.cleanedText)
            links = extraction.links
            fullMd = parsed
            DispatchQueue.main.async {
                cachedMarkdown = parsed
                cachedLinks = links
                lastParsedLength = len
            }
        }
        
        // Build streaming (partial) markdown by truncating at word boundary
        var streamMd = AttributedString()
        if isStreaming && displayedWordCount > 0 && !wordBoundaries.isEmpty {
            let boundaryIdx = min(displayedWordCount, wordBoundaries.count) - 1
            let endIndex = wordBoundaries[boundaryIdx]
            let partial = String(cleanedFullText[cleanedFullText.startIndex..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            streamMd = parseMarkdown(partial)
        } else if isStreaming {
            streamMd = AttributedString()
        }
        
        return (fullMd, links, streamMd)
    }
}

// MARK: - Welcome View (static)
private struct WelcomeView: View {
    let onSuggestion: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 64, height: 64)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 6) {
                Text("Scout")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Your movie & TV assistant")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                SuggestionChip(text: "What should I watch tonight?") {
                    onSuggestion("What should I watch tonight?")
                }
                
                SuggestionChip(text: "Something like Breaking Bad") {
                    onSuggestion("Something like Breaking Bad")
                }
                
                SuggestionChip(text: "Best sci-fi movies ever") {
                    onSuggestion("Best sci-fi movies ever")
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - AI Input Bar
struct AIInputBar: View {
    @Binding var inputText: String
    @Binding var selectedModel: AIService.ChronModel
    let isLoading: Bool
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ModelSelectorRow(selectedModel: $selectedModel)
            
            AIInputTextField(
                inputText: $inputText,
                isLoading: isLoading,
                isInputFocused: isInputFocused,
                onSend: onSend
            )
        }
        .background(Color(.systemGray6))
    }
}

// MARK: - Model Selector
private struct ModelSelectorRow: View, Equatable {
    @Binding var selectedModel: AIService.ChronModel
    
    static func == (lhs: ModelSelectorRow, rhs: ModelSelectorRow) -> Bool {
        lhs.selectedModel == rhs.selectedModel
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(AIService.ChronModel.allCases, id: \.rawValue) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if selectedModel == model {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                    Text(selectedModel.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(.systemGray5))
                .cornerRadius(6)
            }
            .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

// MARK: - Input Text Field
private struct AIInputTextField: View {
    @Binding var inputText: String
    let isLoading: Bool
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    
    private var trimmedEmpty: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextEditor(text: $inputText)
                .focused(isInputFocused)
                .frame(minHeight: 36, maxHeight: 100)
                .fixedSize(horizontal: false, vertical: true)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(18)
                .overlay {
                    if inputText.isEmpty {
                        HStack {
                            Text("Ask Scout anything...")
                                .font(.body)
                                .foregroundColor(Color(.placeholderText))
                                .padding(.leading, 12)
                                .allowsHitTesting(false)
                            Spacer()
                        }
                    }
                }
            
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(trimmedEmpty ? .secondary : .accentColor)
            }
            .disabled(trimmedEmpty || isLoading)
            .padding(.bottom, 4)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Suggestion Chip
struct SuggestionChip: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(16)
        }
        .foregroundColor(.primary)
    }
}

// MARK: - Thinking Bubble
struct ThinkingBubble: View {
    let thinkingText: String
    let userQuery: String
    @State private var isExpanded = false
    @State private var dotPhase = 0
    @State private var placeholderIndex = 0
    
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    private var placeholderPhrases: [String] {
        let query = userQuery.lowercased()
        if query.contains("recommend") || query.contains("suggest") || query.contains("should i watch") || query.contains("what to watch") {
            return [
                "Browsing the catalogue",
                "Matching your taste",
                "Picking the best titles",
                "Curating recommendations"
            ]
        } else if query.contains("like") || query.contains("similar") {
            return [
                "Finding similar titles",
                "Comparing vibes and genres",
                "Looking for the right match",
                "Digging through hidden gems"
            ]
        } else if query.contains("best") || query.contains("top") || query.contains("greatest") {
            return [
                "Ranking the greats",
                "Sorting through the classics",
                "Pulling up the best picks",
                "Reviewing ratings and acclaim"
            ]
        } else if query.contains("explain") || query.contains("what is") || query.contains("who is") || query.contains("tell me about") {
            return [
                "Looking that up",
                "Gathering details",
                "Pulling together info",
                "Checking the facts"
            ]
        } else {
            return [
                "Mulling it over",
                "Searching my memory",
                "Putting thoughts together",
                "Working on a response"
            ]
        }
    }
    
    private var dots: String {
        String(repeating: ".", count: (dotPhase % 3) + 1)
    }
    
    private var thinkingLabel: String {
        let trimmed = thinkingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let phrases = placeholderPhrases
            let idx = placeholderIndex % phrases.count
            return phrases[idx] + dots
        }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let cleaned = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 55 {
            return cleaned + dots
        }
        let truncated = String(cleaned.prefix(52))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[truncated.startIndex..<lastSpace]) + "..." + dots
        }
        return truncated + "..." + dots
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .font(.caption)
                            .foregroundColor(.purple)
                        
                        Text(thinkingLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.purple)
                            .lineLimit(1)
                            .animation(.none, value: thinkingLabel)
                        
                        if !thinkingText.isEmpty {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(.purple.opacity(0.6))
                        }
                    }
                }
                .disabled(thinkingText.isEmpty)
                
                if isExpanded && !thinkingText.isEmpty {
                    Text(thinkingText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(8)
                        .padding(10)
                        .background(Color.purple.opacity(0.06))
                        .cornerRadius(10)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray5).opacity(0.7))
            .cornerRadius(16)
            .frame(maxWidth: 300, alignment: .leading)
            
            Spacer()
        }
        .onReceive(timer) { _ in
            dotPhase += 1
            if dotPhase % 4 == 0 {
                placeholderIndex += 1
            }
        }
    }
}

// MARK: - Markdown Text Helpers

private func cleanAIResponse(_ text: String) -> String {
    var cleaned = text
    
    // Remove markdown reference links like [[1]]() or [[1]](url)
    if let refRegex = try? NSRegularExpression(pattern: "\\[\\[\\d+\\]\\]\\([^)]*\\)", options: []) {
        cleaned = refRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // Remove numbered reference footnotes like [1], [2] etc at end
    if let fnRegex = try? NSRegularExpression(pattern: "\\[\\d+\\]", options: []) {
        cleaned = fnRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // Remove horizontal rules (---, ___, ***)
    cleaned = cleaned.replacingOccurrences(of: "\n---\n", with: "\n")
    cleaned = cleaned.replacingOccurrences(of: "\n___\n", with: "\n")
    cleaned = cleaned.replacingOccurrences(of: "\n***\n", with: "\n")
    
    // Remove markdown headers (# ## ###)
    if let headerRegex = try? NSRegularExpression(pattern: "^#{1,3}\\s+", options: .anchorsMatchLines) {
        cleaned = headerRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // Remove "Related searches:" sections and everything after
    if let relatedRegex = try? NSRegularExpression(pattern: "\\n*Related searches?:.*$", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
        cleaned = relatedRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // Remove "Related questions:" sections
    if let relatedQRegex = try? NSRegularExpression(pattern: "\\n*Related questions?:.*$", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
        cleaned = relatedQRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // Remove "People also ask:" sections
    if let paaRegex = try? NSRegularExpression(pattern: "\\n*People also ask:.*$", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
        cleaned = paaRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // Remove lines starting with "+ " that are related search suggestions
    if let plusLineRegex = try? NSRegularExpression(pattern: "^\\+\\s+.+$", options: .anchorsMatchLines) {
        cleaned = plusLineRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // Remove "Learn more:" sections at the end that reference sources
    if let learnMoreRegex = try? NSRegularExpression(pattern: "\\n*Learn more:.*$", options: [.dotMatchesLineSeparators]) {
        cleaned = learnMoreRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // Remove "Sources:" sections at the end
    if let sourcesRegex = try? NSRegularExpression(pattern: "\\n*Sources?:.*$", options: [.dotMatchesLineSeparators]) {
        cleaned = sourcesRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // Remove [TRAILER:...] tags from display text
    if let trailerTagRegex = try? NSRegularExpression(pattern: "\\[TRAILER:[^\\]]*\\]", options: []) {
        cleaned = trailerTagRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
    }
    
    // --- DEDUPLICATION: Remove repeated blocks of text ---
    cleaned = deduplicateResponse(cleaned)
    
    // Clean up excessive newlines
    cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    
    return cleaned
}

/// Detects and removes duplicated paragraphs/blocks within a response.
/// Splits by double-newline into paragraphs, then removes any paragraph that
/// is a near-duplicate of an earlier one (using normalized comparison).
private func deduplicateResponse(_ text: String) -> String {
    // Split into paragraphs (blocks separated by blank lines)
    let paragraphs = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    
    guard paragraphs.count > 1 else { return text }
    
    var seen: [String] = []
    var result: [String] = []
    
    for paragraph in paragraphs {
        // Normalize: lowercase, collapse whitespace, strip markdown bold markers and punctuation differences
        let normalized = paragraph
            .lowercased()
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if this paragraph is a near-duplicate of any we've already kept
        let isDuplicate = seen.contains { existing in
            // Exact match after normalization
            if existing == normalized { return true }
            // Check if one is a substantial substring of the other (>70% overlap)
            let shorter = min(existing.count, normalized.count)
            let longer = max(existing.count, normalized.count)
            guard shorter > 40 else { return false } // only dedup non-trivial blocks
            // Use Jaccard-like word overlap
            let existingWords = Set(existing.components(separatedBy: .whitespaces))
            let normalizedWords = Set(normalized.components(separatedBy: .whitespaces))
            let intersection = existingWords.intersection(normalizedWords).count
            let union = existingWords.union(normalizedWords).count
            guard union > 0 else { return false }
            let similarity = Double(intersection) / Double(union)
            return similarity > 0.7
        }
        
        if !isDuplicate {
            seen.append(normalized)
            result.append(paragraph)
        }
    }
    
    return result.joined(separator: "\n\n")
}

private func parseMarkdown(_ text: String) -> AttributedString {
    let cleaned = cleanAIResponse(text)
    var result = AttributedString()
    let lines = cleaned.components(separatedBy: "\n")
    
    for (lineIndex, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Skip pure separator lines
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            continue
        }
        
        let isBullet = trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ")
        // Numbered list items like "1. " or "2. "
        let isNumberedList = trimmed.range(of: "^\\d+\\.\\s", options: .regularExpression) != nil
        
        if isBullet {
            var bulletPrefix = AttributedString("  • ")
            bulletPrefix.font = .body
            result.append(bulletPrefix)
            
            let content = String(trimmed.dropFirst(2))
            result.append(parseInlineFormatting(content))
        } else if isNumberedList {
            // Keep the number but style it
            result.append(parseInlineFormatting("  " + trimmed))
        } else {
            result.append(parseInlineFormatting(line))
        }
        
        if lineIndex < lines.count - 1 {
            result.append(AttributedString("\n"))
        }
    }
    
    return result
}

private func parseInlineFormatting(_ text: String) -> AttributedString {
    var result = AttributedString()
    var remaining = text[text.startIndex...]
    
    while let boldStart = remaining.range(of: "**") {
        let before = remaining[remaining.startIndex..<boldStart.lowerBound]
        if !before.isEmpty {
            var attr = AttributedString(String(before))
            attr.font = .body
            result.append(attr)
        }
        
        let afterStart = boldStart.upperBound
        let searchRange = afterStart..<remaining.endIndex
        if let boldEnd = remaining.range(of: "**", range: searchRange) {
            let boldContent = remaining[afterStart..<boldEnd.lowerBound]
            var boldAttr = AttributedString(String(boldContent))
            boldAttr.font = .body.bold()
            result.append(boldAttr)
            remaining = remaining[boldEnd.upperBound...]
        } else {
            // No closing **, just append the rest as normal text
            var attr = AttributedString(String(remaining[boldStart.lowerBound...]))
            attr.font = .body
            result.append(attr)
            return result
        }
    }
    
    if !remaining.isEmpty {
        var attr = AttributedString(String(remaining))
        attr.font = .body
        result.append(attr)
    }
    
    return result
}

// MARK: - Source Link Chip
private struct SourceLinkChip: View {
    let link: ExtractedLink
    
    var body: some View {
        Button {
            UIApplication.shared.open(link.url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                Text(domainDisplayName(from: link.url))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .foregroundColor(.accentColor)
            .cornerRadius(10)
        }
    }
}

// MARK: - Source Links Flow Layout
private struct SourceLinksFlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        
        return CGSize(width: maxWidth, height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Blinking Cursor
private struct BlinkingCursor: View {
    @State private var visible = true
    
    var body: some View {
        Text("|")
            .font(.body)
            .foregroundColor(.accentColor)
            .opacity(visible ? 0.9 : 0.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: AIService.ChatMessage
    let parsedMarkdown: AttributedString
    var links: [ExtractedLink] = []
    var trailerKey: String?
    var trailerTitle: String?
    var isStreaming: Bool = false
    
    @State private var showTrailerPlayer = false
    @State private var showThinking = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var isUser: Bool { message.role == "user" }
    
    private var assistantBubbleColor: Color {
        colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)
    }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        Text("Scout")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)
                }
                
                if let thinking = message.thinkingContent, !thinking.isEmpty, !isUser {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showThinking.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.system(size: 9))
                            Text("Thought process")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Image(systemName: showThinking ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7))
                        }
                        .foregroundColor(.purple.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(8)
                    }
                    
                    if showThinking {
                        Text(thinking)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(12)
                            .padding(10)
                            .background(Color.purple.opacity(0.05))
                            .cornerRadius(10)
                            .transition(.opacity)
                    }
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        if isUser {
                            Text(message.content)
                                .font(.body)
                        } else {
                            Text(parsedMarkdown)
                        }
                        
                        if isStreaming {
                            BlinkingCursor()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    isUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(assistantBubbleColor)
                )
                .foregroundColor(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                // Source links below the bubble
                if !isUser && !links.isEmpty && !isStreaming {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SOURCES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.secondary.opacity(0.6))
                            .tracking(0.8)
                        
                        SourceLinksFlowLayout(spacing: 6) {
                            ForEach(links) { link in
                                SourceLinkChip(link: link)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 4)
                }
                
                if let key = trailerKey, let title = trailerTitle, !isUser {
                    Button {
                        showTrailerPlayer = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Watch Trailer")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(title)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
                        )
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: 260)
                    .sheet(isPresented: $showTrailerPlayer) {
                        TrailerPlayerSheet(videoKey: key, title: title)
                    }
                }
            }
            .frame(maxWidth: 320, alignment: isUser ? .trailing : .leading)
            
            if !isUser { Spacer() }
        }
    }
}

// Helper for type-erased ShapeStyle
private struct AnyShapeStyle: ShapeStyle {
    private let _resolve: (inout EnvironmentValues) -> Color
    
    init(_ color: Color) {
        _resolve = { _ in color }
    }
    
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        var env = environment
        return _resolve(&env)
    }
}

// MARK: - Trailer Player Sheet
struct TrailerPlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                
                InAppYouTubePlayer(videoKey: videoKey)
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                
                Spacer()
            }
            .background(Color.black)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Lightweight Input State
@MainActor
class AIInputState: ObservableObject {
    @Published var inputText = ""
    @Published var selectedModel: AIService.ChronModel = .gemini25Flash
    @Published var isLoading = false
    
    private let modelKey = "chron_selected_model"
    
    init() {
        if let savedModel = UserDefaults.standard.string(forKey: modelKey),
           let model = AIService.ChronModel(rawValue: savedModel) {
            selectedModel = model
        }
    }
    
    func saveModel() {
        UserDefaults.standard.set(selectedModel.rawValue, forKey: modelKey)
    }
}

// MARK: - View Model
@MainActor
class AIAssistantViewModel: ObservableObject {
    @Published var messages: [AIService.ChatMessage] = []
    @Published var messageCount: Int = 0 // Lightweight counter for conditional checks
    @Published var isThinking = false
    @Published var currentThinkingText = ""
    @Published var streamingMessageId: String? = nil
    @Published var webSearchEnabled = true
    @Published var trailerMessages: [String: (trailerKey: String, trailerTitle: String)] = [:]
    @Published var scrollTrigger = 0
    @Published var currentUserQuery = ""
    
    let inputState = AIInputState()
    
    // Aggressive throttle: buffer content and only push to UI periodically
    private var lastPublishTime: CFAbsoluteTime = 0
    private static let publishInterval: CFAbsoluteTime = 0.12 // ~8fps for content updates
    private static let charThreshold = 40 // minimum chars between UI pushes
    private var lastPublishedLength = 0
    private var pendingFlushTask: Task<Void, Never>?
    
    func sendMessage() async {
        let userMessage = inputState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        let userChatMessage = AIService.ChatMessage(role: "user", content: userMessage)
        messages.append(userChatMessage)
        messageCount = messages.count
        inputState.inputText = ""
        scrollTrigger += 1
        
        inputState.isLoading = true
        isThinking = true
        currentThinkingText = ""
        currentUserQuery = userMessage
        
        inputState.saveModel()
        
        let selectedModel = inputState.selectedModel
        
        // Check for trailer short-circuit first (non-streaming)
        let lowercased = userMessage.lowercased()
        let trailerKeywords = ["trailer", "teaser", "preview"]
        let isTrailerRequest = trailerKeywords.contains { lowercased.contains($0) }
        
        if isTrailerRequest {
            do {
                let likedItems = StorageService.shared.liked
                let (response, trailerResponse) = try await AIService.shared.sendMessage(
                    userMessage,
                    conversationHistory: messages,
                    likedItems: likedItems,
                    webSearchEnabled: webSearchEnabled,
                    model: selectedModel
                )
                
                isThinking = false
                
                // Check for [TRAILER:] tags in the response
                let (cleanedContent, trailerTitles) = AIService.extractTrailerTags(from: response)
                let assistantMessage = AIService.ChatMessage(role: "assistant", content: cleanedContent)
                messages.append(assistantMessage)
                messageCount = messages.count
                
                // Priority: direct trailer response from short-circuit, then tag-based lookup
                if let trailer = trailerResponse {
                    trailerMessages[assistantMessage.id] = (trailer.trailerKey, trailer.trailerTitle)
                } else if let firstTitle = trailerTitles.first {
                    // Fetch trailer from TMDB based on the tag
                    if let result = await AIService.shared.fetchTrailer(for: firstTitle) {
                        trailerMessages[assistantMessage.id] = (result.key, result.title)
                    }
                }
                
                inputState.isLoading = false
                scrollTrigger += 1
                return
            } catch {
                isThinking = false
                let errorMessage = AIService.ChatMessage(role: "assistant", content: "Couldn't look that up — \(error.localizedDescription)")
                messages.append(errorMessage)
                messageCount = messages.count
                inputState.isLoading = false
                scrollTrigger += 1
                return
            }
        }
        
        // Streaming path
        let likedItems = StorageService.shared.liked
        
        let streamingMessage = AIService.ChatMessage(role: "assistant", content: "")
        messages.append(streamingMessage)
        messageCount = messages.count
        let streamIndex = messages.count - 1
        streamingMessageId = streamingMessage.id
        lastPublishedLength = 0
        lastPublishTime = CFAbsoluteTimeGetCurrent()
        scrollTrigger += 1
        
        var accumulatedThinking = ""
        var pendingContent = ""
        
        let stream = await AIService.shared.streamMessage(
            userMessage,
            conversationHistory: Array(messages.dropLast()),
            likedItems: likedItems,
            webSearchEnabled: webSearchEnabled,
            model: selectedModel
        )
        
        for await event in stream {
            switch event {
            case .thinking(let text):
                accumulatedThinking = text
                // Throttle thinking updates aggressively
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastPublishTime > 0.25 {
                    currentThinkingText = text
                    lastPublishTime = now
                }
                
            case .content(let text):
                if isThinking {
                    isThinking = false
                    currentThinkingText = accumulatedThinking
                }
                pendingContent = text
                
                // Time + char based throttle — only push when enough time AND content has elapsed
                let now = CFAbsoluteTimeGetCurrent()
                let charDelta = text.count - lastPublishedLength
                let timeDelta = now - lastPublishTime
                
                if (charDelta >= Self.charThreshold && timeDelta >= Self.publishInterval) || text.count < 20 {
                    pendingFlushTask?.cancel()
                    messages[streamIndex].content = text
                    lastPublishedLength = text.count
                    lastPublishTime = now
                    scrollTrigger += 1
                } else if pendingFlushTask == nil || pendingFlushTask?.isCancelled == true {
                    // Schedule a deferred flush so content doesn't stall
                    let capturedText = text
                    pendingFlushTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                        guard !Task.isCancelled, let self else { return }
                        if streamIndex < self.messages.count {
                            self.messages[streamIndex].content = capturedText
                            self.lastPublishedLength = capturedText.count
                            self.lastPublishTime = CFAbsoluteTimeGetCurrent()
                            self.scrollTrigger += 1
                        }
                    }
                }
                
            case .done:
                pendingFlushTask?.cancel()
                // Flush any remaining pending content
                if !pendingContent.isEmpty {
                    messages[streamIndex].content = pendingContent
                }
                if !accumulatedThinking.isEmpty {
                    messages[streamIndex].thinkingContent = accumulatedThinking
                }
                streamingMessageId = nil
                isThinking = false
                
                // Extract [TRAILER:Title] tags and fetch trailer from TMDB
                let finalContent = messages[streamIndex].content
                let (cleanedContent, trailerTitles) = AIService.extractTrailerTags(from: finalContent)
                if cleanedContent != finalContent {
                    messages[streamIndex].content = cleanedContent
                }
                if let firstTitle = trailerTitles.first {
                    let msgId = messages[streamIndex].id
                    if let result = await AIService.shared.fetchTrailer(for: firstTitle) {
                        trailerMessages[msgId] = (result.key, result.title)
                    }
                }
                
                inputState.isLoading = false
                scrollTrigger += 1
                
            case .error(let error):
                pendingFlushTask?.cancel()
                isThinking = false
                streamingMessageId = nil
                messages[streamIndex].content = "Sorry, something went wrong: \(error.localizedDescription)"
                inputState.isLoading = false
                scrollTrigger += 1
            }
        }
        
        // Safety: ensure loading states are cleared
        pendingFlushTask?.cancel()
        inputState.isLoading = false
        isThinking = false
        streamingMessageId = nil
    }
    
    func clearMessages() {
        pendingFlushTask?.cancel()
        messages = []
        messageCount = 0
        trailerMessages = [:]
        currentThinkingText = ""
        currentUserQuery = ""
        isThinking = false
        streamingMessageId = nil
    }
}

#Preview {
    AIAssistantView()
}
