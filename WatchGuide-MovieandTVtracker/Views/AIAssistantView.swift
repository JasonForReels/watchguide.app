//
//  AIAssistantView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct AIAssistantView: View {
    @StateObject private var viewModel = AIAssistantViewModel()
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if viewModel.messages.isEmpty {
                                welcomeView
                            }
                            
                            ForEach(viewModel.messages) { message in
                                MessageBubble(
                                    message: message,
                                    trailerKey: viewModel.trailerMessages[message.id]?.trailerKey,
                                    trailerTitle: viewModel.trailerMessages[message.id]?.trailerTitle,
                                    isStreaming: viewModel.streamingMessageId == message.id
                                )
                                .id(message.id)
                            }
                            
                            // Thinking indicator
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
                        withAnimation(.easeOut(duration: 0.2)) {
                            if let streamId = viewModel.streamingMessageId {
                                proxy.scrollTo(streamId, anchor: .bottom)
                            } else if viewModel.isThinking {
                                proxy.scrollTo("thinking", anchor: .bottom)
                            } else {
                                proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                            }
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            isInputFocused = false
                        }
                    )
                }
                
                Divider()
                
                // Bottom bar — extracted to isolate redraws from the message list
                AIInputBar(viewModel: viewModel, isInputFocused: $isInputFocused, onSend: sendMessage)
            }
            .navigationTitle("Chron")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.clearMessages()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline)
                    }
                    .disabled(viewModel.messages.isEmpty)
                }
            }
        }
    }
    
    private var welcomeView: some View {
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
            
            // Quick suggestions
            VStack(spacing: 8) {
                SuggestionChip(text: "What should I watch tonight?") {
                    viewModel.inputText = "What should I watch tonight?"
                    sendMessage()
                }
                
                SuggestionChip(text: "Something like Breaking Bad") {
                    viewModel.inputText = "Something like Breaking Bad"
                    sendMessage()
                }
                
                SuggestionChip(text: "Best sci-fi movies ever") {
                    viewModel.inputText = "Best sci-fi movies ever"
                    sendMessage()
                }
            }
            .padding(.top, 8)
        }
    }
    
    private func sendMessage() {
        guard !viewModel.inputText.isEmpty else { return }
        Task {
            await viewModel.sendMessage()
        }
    }
}

// MARK: - AI Input Bar (isolated to prevent redraw propagation)
struct AIInputBar: View {
    @ObservedObject var viewModel: AIAssistantViewModel
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Model selector (compact)
            modelSelector
            
            // Input area
            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $viewModel.inputText)
                    .focused(isInputFocused)
                    .frame(minHeight: 36, maxHeight: 100)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(18)
                    .overlay {
                        if viewModel.inputText.isEmpty {
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
                        .foregroundColor(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                .padding(.bottom, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGray6))
    }
    
    private var modelSelector: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(AIService.ChronModel.allCases, id: \.rawValue) { model in
                    Button {
                        viewModel.selectedModel = model
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if viewModel.selectedModel == model {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                    Text(viewModel.selectedModel.displayName)
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
    
    /// Contextual placeholder phrases when no real thinking text is available
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
    
    /// Derive a short label from the thinking text, or cycle through contextual placeholders
    private var thinkingLabel: String {
        let trimmed = thinkingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let phrases = placeholderPhrases
            let idx = placeholderIndex % phrases.count
            return phrases[idx] + dots
        }
        // Take the first meaningful sentence/phrase, truncate to ~50 chars
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let cleaned = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 55 {
            return cleaned + dots
        }
        // Truncate at word boundary
        let truncated = String(cleaned.prefix(52))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[truncated.startIndex..<lastSpace]) + "..." + dots
        }
        return truncated + "..." + dots
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                // Thinking header with live snippet
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
                
                // Expandable full thinking content
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
            // Cycle placeholder every 2 ticks (~1 second)
            if dotPhase % 4 == 0 {
                placeholderIndex += 1
            }
        }
    }
}

// MARK: - Markdown Text Helpers

/// Parse simple markdown: **bold** and bullet points (* item)
private func parseMarkdown(_ text: String) -> AttributedString {
    var result = AttributedString()
    let lines = text.components(separatedBy: "\n")
    
    for (lineIndex, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Check if this is a bullet point line (starts with "* " or "- ")
        let isBullet = trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ")
        
        if isBullet {
            // Add bullet character and parse the rest for bold
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

/// Parse **bold** markers within a line
private func parseBoldSegments(_ text: String) -> AttributedString {
    var result = AttributedString()
    var remaining = text[text.startIndex...]
    
    while let boldStart = remaining.range(of: "**") {
        // Add text before the bold marker
        let before = remaining[remaining.startIndex..<boldStart.lowerBound]
        if !before.isEmpty {
            var attr = AttributedString(String(before))
            attr.font = .body
            result.append(attr)
        }
        
        // Look for closing **
        let afterStart = boldStart.upperBound
        let searchRange = afterStart..<remaining.endIndex
        if let boldEnd = remaining.range(of: "**", range: searchRange) {
            let boldContent = remaining[afterStart..<boldEnd.lowerBound]
            var boldAttr = AttributedString(String(boldContent))
            boldAttr.font = .body.bold()
            result.append(boldAttr)
            remaining = remaining[boldEnd.upperBound...]
        } else {
            // No closing **, treat the ** as literal text
            var attr = AttributedString(String(remaining[boldStart.lowerBound...]))
            attr.font = .body
            result.append(attr)
            return result
        }
    }
    
    // Add any remaining text
    if !remaining.isEmpty {
        var attr = AttributedString(String(remaining))
        attr.font = .body
        result.append(attr)
    }
    
    return result
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: AIService.ChatMessage
    var trailerKey: String?
    var trailerTitle: String?
    var isStreaming: Bool = false
    
    @State private var showTrailerPlayer = false
    @State private var showThinking = false
    
    var isUser: Bool {
        message.role == "user"
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
                        Text("Chron")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Collapsible thinking section (for completed messages)
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
                
                // Main content with markdown rendering
                HStack(spacing: 0) {
                    if isUser {
                        Text(message.content)
                            .font(.body)
                    } else {
                        Text(parseMarkdown(message.content))
                    }
                    
                    // Streaming cursor
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
                
                // Trailer button
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

// MARK: - View Model
@MainActor
class AIAssistantViewModel: ObservableObject {
    @Published var messages: [AIService.ChatMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var isThinking = false
    @Published var currentThinkingText = ""
    @Published var streamingMessageId: String? = nil
    @Published var selectedModel: AIService.ChronModel = .gemini25Flash
    @Published var webSearchEnabled = true
    @Published var trailerMessages: [String: (trailerKey: String, trailerTitle: String)] = [:]
    @Published var scrollTrigger = 0
    @Published var currentUserQuery = ""
    
    private let modelKey = "chron_selected_model"
    
    init() {
        if let savedModel = UserDefaults.standard.string(forKey: modelKey),
           let model = AIService.ChronModel(rawValue: savedModel) {
            selectedModel = model
        }
    }
    
    func sendMessage() async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        let userChatMessage = AIService.ChatMessage(role: "user", content: userMessage)
        messages.append(userChatMessage)
        inputText = ""
        scrollTrigger += 1
        
        isLoading = true
        isThinking = true
        currentThinkingText = ""
        currentUserQuery = userMessage
        
        UserDefaults.standard.set(selectedModel.rawValue, forKey: modelKey)
        
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
                
                isLoading = false
                scrollTrigger += 1
                return
            } catch {
                isThinking = false
                let errorMessage = AIService.ChatMessage(role: "assistant", content: "Couldn't look that up — \(error.localizedDescription)")
                messages.append(errorMessage)
                isLoading = false
                scrollTrigger += 1
                return
            }
        }
        
        // Streaming path
        let likedItems = StorageService.shared.liked
        
        // Create a placeholder assistant message for streaming
        var streamingMessage = AIService.ChatMessage(role: "assistant", content: "")
        messages.append(streamingMessage)
        let streamIndex = messages.count - 1
        streamingMessageId = streamingMessage.id
        scrollTrigger += 1
        
        var accumulatedThinking = ""
        
        let stream = await AIService.shared.streamMessage(
            userMessage,
            conversationHistory: Array(messages.dropLast()),  // exclude placeholder
            likedItems: likedItems,
            webSearchEnabled: webSearchEnabled,
            model: selectedModel
        )
        
        for await event in stream {
            switch event {
            case .thinking(let text):
                accumulatedThinking = text
                currentThinkingText = text
                scrollTrigger += 1
                
            case .content(let text):
                if isThinking {
                    isThinking = false
                }
                messages[streamIndex].content = text
                // Throttle scroll updates
                if text.count % 8 == 0 || text.count < 10 {
                    scrollTrigger += 1
                }
                
            case .done:
                // Store thinking content on the message
                if !accumulatedThinking.isEmpty {
                    messages[streamIndex].thinkingContent = accumulatedThinking
                }
                streamingMessageId = nil
                isThinking = false
                isLoading = false
                scrollTrigger += 1
                
            case .error(let error):
                isThinking = false
                streamingMessageId = nil
                messages[streamIndex].content = "Sorry, something went wrong: \(error.localizedDescription)"
                isLoading = false
                scrollTrigger += 1
            }
        }
        
        // Safety: ensure loading states are cleared
        isLoading = false
        isThinking = false
        streamingMessageId = nil
    }
    
    func clearMessages() {
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
