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
                .navigationTitle("Chron")
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

/// Isolated clear-button — only observes messageCount via a simple count
private struct ClearButton: View {
    @ObservedObject var viewModel: AIAssistantViewModel
    
    var body: some View {
        Button {
            viewModel.clearMessages()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.subheadline)
        }
        .disabled(viewModel.messages.isEmpty)
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
                    if viewModel.messages.isEmpty {
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
                DragGesture().onChanged { _ in dismissKeyboard() }
            )
        }
    }
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
    
    var body: some View {
        let (md, links) = currentContent
        MessageBubble(
            message: message,
            parsedMarkdown: md,
            links: links,
            trailerKey: trailerKey,
            trailerTitle: trailerTitle,
            isStreaming: isStreaming
        )
    }
    
    private var currentContent: (AttributedString, [ExtractedLink]) {
        if message.role == "user" { return (AttributedString(), []) }
        let len = message.content.count
        if len == lastParsedLength, let cached = cachedMarkdown {
            return (cached, cachedLinks)
        }
        let extraction = extractLinks(from: message.content)
        let parsed = parseMarkdown(extraction.cleanedText)
        let links = extraction.links
        DispatchQueue.main.async {
            cachedMarkdown = parsed
            cachedLinks = links
            lastParsedLength = len
        }
        return (parsed, links)
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
                Text("Chron")
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
                            Text("Ask Chron anything...")
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

private func parseMarkdown(_ text: String) -> AttributedString {
    var result = AttributedString()
    let lines = text.components(separatedBy: "\n")
    
    for (lineIndex, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let isBullet = trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ")
        
        if isBullet {
            var bulletPrefix = AttributedString("• ")
            bulletPrefix.font = .body
            result.append(bulletPrefix)
            
            let content = String(trimmed.dropFirst(2))
            result.append(parseBoldSegments(content))
        } else {
            result.append(parseBoldSegments(line))
        }
        
        if lineIndex < lines.count - 1 {
            result.append(AttributedString("\n"))
        }
    }
    
    return result
}

private func parseBoldSegments(_ text: String) -> AttributedString {
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
    
    private var isUser: Bool { message.role == "user" }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        Text("Chron")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
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
                            Image(systemName: showThinking ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7))
                        }
                        .foregroundColor(.purple.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(8)
                    }
                    
                    if showThinking {
                        Text(thinking)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(12)
                            .padding(8)
                            .background(Color.purple.opacity(0.05))
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                }
                
                HStack(spacing: 0) {
                    if isUser {
                        Text(message.content)
                            .font(.body)
                    } else {
                        Text(parsedMarkdown)
                    }
                    
                    if isStreaming {
                        Text("|")
                            .font(.body)
                            .foregroundColor(.accentColor)
                            .opacity(0.8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.accentColor : Color(.systemGray5))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)
                
                // Source links below the bubble
                if !isUser && !links.isEmpty && !isStreaming {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        SourceLinksFlowLayout(spacing: 6) {
                            ForEach(links) { link in
                                SourceLinkChip(link: link)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                
                if let key = trailerKey, let title = trailerTitle, !isUser {
                    Button {
                        showTrailerPlayer = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
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
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: 260)
                    .sheet(isPresented: $showTrailerPlayer) {
                        TrailerPlayerSheet(videoKey: key, title: title)
                    }
                }
            }
            .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
            
            if !isUser { Spacer() }
        }
    }
}

// MARK: - Trailer Player Sheet
struct TrailerPlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    
    private var thumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(videoKey)/maxresdefault.jpg")
    }
    
    private var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(videoKey)")
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                ZStack {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16.0/9.0, contentMode: .fit)
                        case .failure, .empty:
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .aspectRatio(16.0/9.0, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "play.rectangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                }
                        @unknown default:
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .aspectRatio(16.0/9.0, contentMode: .fit)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.5))
                            .frame(width: 64, height: 64)
                        Image(systemName: "play.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .offset(x: 2)
                    }
                }
                .onTapGesture {
                    if let url = youtubeURL {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.horizontal)
                
                Button {
                    if let url = youtubeURL {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Watch on YouTube", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
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
    private static let publishInterval: CFAbsoluteTime = 0.08 // ~12fps max for content updates
    private static let charThreshold = 30 // minimum chars between UI pushes
    private var lastPublishedLength = 0
    private var pendingFlushTask: Task<Void, Never>?
    
    func sendMessage() async {
        let userMessage = inputState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        let userChatMessage = AIService.ChatMessage(role: "user", content: userMessage)
        messages.append(userChatMessage)
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
                let assistantMessage = AIService.ChatMessage(role: "assistant", content: response)
                messages.append(assistantMessage)
                
                if let trailer = trailerResponse {
                    trailerMessages[assistantMessage.id] = (trailer.trailerKey, trailer.trailerTitle)
                }
                
                inputState.isLoading = false
                scrollTrigger += 1
                return
            } catch {
                isThinking = false
                let errorMessage = AIService.ChatMessage(role: "assistant", content: "Couldn't look that up — \(error.localizedDescription)")
                messages.append(errorMessage)
                inputState.isLoading = false
                scrollTrigger += 1
                return
            }
        }
        
        // Streaming path
        let likedItems = StorageService.shared.liked
        
        let streamingMessage = AIService.ChatMessage(role: "assistant", content: "")
        messages.append(streamingMessage)
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
                // Throttle thinking updates too
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastPublishTime > 0.15 {
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
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
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
