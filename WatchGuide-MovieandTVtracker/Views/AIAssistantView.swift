//
//  AIAssistantView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

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

// MARK: - Atlas Immersive Background
private struct AtlasBackground: View {
    var body: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.04, blue: 0.20),
                    Color(red: 0.03, green: 0.02, blue: 0.13),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(red: 0.38, green: 0.28, blue: 0.90).opacity(0.55), Color.clear],
                center: UnitPoint(x: 0.15, y: 0.06),
                startRadius: 20, endRadius: 380
            )
            RadialGradient(
                colors: [Color(red: 0.16, green: 0.32, blue: 0.92).opacity(0.30), Color.clear],
                center: UnitPoint(x: 0.88, y: 0.10),
                startRadius: 30, endRadius: 300
            )
            RadialGradient(
                colors: [Color(red: 0.26, green: 0.18, blue: 0.68).opacity(0.22), Color.clear],
                center: .bottom,
                startRadius: 40, endRadius: 280
            )
        }
    }
}

// MARK: - Atlas Tab
private enum AtlasTab { case chat, imagine }

private struct AtlasTabPicker: View {
    @Binding var selectedTab: AtlasTab

    private let selectedTint = Color(red: 0.30, green: 0.42, blue: 0.95)

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    glassTab(.chat, label: "Chat", icon: "bubble.left.and.bubble.right.fill")
                    glassTab(.imagine, label: "Imagine", icon: "wand.and.stars")
                }
            }
        } else {
            legacyBody
        }
    }

    // MARK: True Liquid Glass (iOS 26+)

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @ViewBuilder
    private func glassTab(_ tab: AtlasTab, label: String, icon: String) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.smooth(duration: 0.3)) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected
                ? .regular.tint(selectedTint.opacity(0.85)).interactive()
                : .regular.interactive()
        )
    }

    // MARK: Pre-iOS 26 fallback

    private var legacyBody: some View {
        HStack(spacing: 0) {
            tabButton(.chat, label: "Chat", icon: "bubble.left.and.bubble.right.fill")
            tabButton(.imagine, label: "Imagine", icon: "wand.and.stars")
        }
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func tabButton(_ tab: AtlasTab, label: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.42))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedTab == tab ? Color.white.opacity(0.15) : Color.clear)
                    .padding(2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model Selector
/// Lets the user pick which AI model powers Atlas — "Auto" (smart routing) plus
/// the individual models. The choice is persisted in UserDefaults and read by
/// `AIService` when building each request.
private struct ModelSelectorMenu: View {
    @AppStorage(AIModelCatalog.selectionDefaultsKey) private var selectedModelId: String = "auto"

    private var current: AIModelOption {
        // A forced model overrides whatever is stored.
        if let forcedId = AIModelCatalog.forcedModelId, let forced = AIModelCatalog.option(id: forcedId) {
            return forced
        }
        return AIModelCatalog.option(id: selectedModelId) ?? AIModelCatalog.auto
    }

    var body: some View {
        Menu {
            if let forcedId = AIModelCatalog.forcedModelId, let forced = AIModelCatalog.option(id: forcedId) {
                // TEMP: only one model is available right now.
                Picker("Model", selection: $selectedModelId) {
                    Text(forced.displayName).tag(forced.id)
                }
            } else {
                // Chat runs on two models only. "Auto" smart-routes between them
                // (web/reasoning), same split as before, now served by OpenRouter.
                Picker("Model", selection: $selectedModelId) {
                    Label("Auto", systemImage: "wand.and.stars")
                        .tag(AIModelCatalog.auto.id)

                    Section("Models") {
                        ForEach(AIModelCatalog.chatModels) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                Text(current.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

// MARK: - Top-level shell (owns the StateObject, body is trivially cheap)
struct AIAssistantView: View {
    // Shared, not owned: AtlasDockBar shows the same conversation, so opening
    // the full surface from the bar continues it instead of starting over.
    @ObservedObject private var viewModel = AIAssistantViewModel.shared
    @State private var atlasTab: AtlasTab = .chat

    var body: some View {
        ZStack {
            AtlasBackground()
                .ignoresSafeArea()
            AIAssistantBody(viewModel: viewModel, atlasTab: $atlasTab)
        }
        .navigationTitle("Ask Atlas")
        #if !os(macOS) && !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ClearButton(viewModel: viewModel)
                    .opacity(atlasTab == .chat ? 1 : 0)
                    .disabled(atlasTab != .chat)
            }
        }
        #if !os(macOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .preferredColorScheme(.dark)
        // The HUD refreshes this on foreground, but Atlas can also be opened
        // from places the HUD isn't (tvOS, the More hub) — so refresh here too.
        .task { AtlasProactiveEngine.shared.refresh() }
        .sheet(isPresented: $viewModel.showUpgradePaywall) {
            WGUnlimitedPaywallView()
        }
        #if os(iOS)
        // Leaving Atlas hangs up: an open microphone on a screen the user has
        // walked away from is not a thing we ship.
        .onDisappear { AtlasInlineVoice.shared.end() }
        #endif
    }
}

// MARK: - Body (layout only — no observation, just passes references)
private struct AIAssistantBody: View {
    let viewModel: AIAssistantViewModel
    @Binding var atlasTab: AtlasTab
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            AtlasTabPicker(selectedTab: $atlasTab)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if atlasTab == .chat {
                HStack {
                    Spacer()
                    ModelSelectorMenu()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

                AIMessageListView(viewModel: viewModel,
                                  dismissKeyboard: { isInputFocused = false })

                AIQuotaStatusBar(
                    remainingMessages: viewModel.remainingMessages,
                    hasScoutUnlimited: viewModel.hasScoutUnlimited,
                    hasPlusOrAbove: viewModel.hasPlusOrAbove
                )

                AIInputBarContainer(
                    inputState: viewModel.inputState,
                    isInputFocused: $isInputFocused,
                    onSend: {
                        Task { await viewModel.sendMessage() }
                    }
                )
            } else {
                AtlasImagineView { imageData in
                    viewModel.inputState.addImage(imageData)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        atlasTab = .chat
                    }
                    isInputFocused = true
                }
            }
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

// MARK: - AI Quota Status Bar
private struct AIQuotaStatusBar: View {
    let remainingMessages: Int
    let hasScoutUnlimited: Bool
    let hasPlusOrAbove: Bool
    @State private var showPaywall = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom)
                )
            if hasScoutUnlimited {
                Text("Unlimited")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.40))
                Spacer()
            } else if hasPlusOrAbove {
                Text("\(remainingMessages) messages left today")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(remainingMessages <= 2 ? 0.75 : 0.40))
                Spacer()
                Button {
                    showPaywall = true
                } label: {
                    Text("Go Unlimited")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange.opacity(0.90))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showPaywall) {
                    WGSubscriptionPaywallView(context: .unlimited)
                }
            } else {
                Text("\(remainingMessages) free messages left")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(remainingMessages <= 1 ? 0.75 : 0.40))
                Spacer()
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                        Text("Upgrade")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showPaywall) {
                    WGSubscriptionPaywallView(context: .plus)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            Color.white.opacity(0.04)
                .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5), alignment: .top)
        )
    }
}

// MARK: - Atlas Privacy Sheet
struct AtlasPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 20)
                    
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.blue.opacity(0.15), Color.clear],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                    }
                    .frame(height: 120)
                    
                    VStack(spacing: 16) {
                        Text("Atlas Privacy & Safety")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 14) {
                            privacyBullet(
                                icon: "shield.checkered",
                                color: .blue,
                                text: "No conversations or data are ever sent to third-party AI providers beyond what is needed to generate your response."
                            )
                            
                            privacyBullet(
                                icon: "eye.slash.fill",
                                color: .purple,
                                text: "Your chat history is stored only on your device and is never uploaded or shared."
                            )
                            
                            privacyBullet(
                                icon: "person.badge.shield.checkmark.fill",
                                color: .green,
                                text: "Content filtering is always active. Atlas will never generate explicit, graphic, or age-inappropriate content."
                            )
                        }
                        .padding(.horizontal, 4)
                    }
                    
                    // Current mode indicator
                    HStack(spacing: 8) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.blue)
                        Text("Content filtered (13+ safe)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private func privacyBullet(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            isLoading: inputState.isLoading,
            isAgentModeEnabled: $inputState.isAgentModeEnabled,
            attachedImages: $inputState.attachedImages,
            isInputFocused: isInputFocused,
            onSend: onSend
        )
    }
}

// MARK: - Message List (observes ViewModel for structural changes only)
struct AIMessageListView: View {
    @ObservedObject var viewModel: AIAssistantViewModel
    let dismissKeyboard: () -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if viewModel.messageCount == 0 {
                        AtlasBriefingCard { prompt in
                            viewModel.inputState.inputText = prompt
                            Task { await viewModel.sendMessage() }
                        }
                        WelcomeView(onSuggestion: { text in
                            viewModel.inputState.inputText = text
                            Task { await viewModel.sendMessage() }
                        })
                    }
                    
                    ForEach(viewModel.messages) { message in
                        let isStreaming = viewModel.streamingMessageId == message.id
                        let trailer = viewModel.trailerMessages[message.id]
                        let playlist = viewModel.playlistMessages[message.id]
                        let isSaved = viewModel.playlistSavedToList[message.id] ?? false
                        let filterPanel = viewModel.filterPanelMessages[message.id]
                        MessageBubbleWrapper(
                            message: message,
                            trailerKey: trailer?.trailerKey,
                            trailerTitle: trailer?.trailerTitle,
                            playlistItems: playlist,
                            isSavedToList: isSaved,
                            filterPanel: filterPanel,
                            onCreateList: { panel in viewModel.createListFromPanel(panel) },
                            onRemovePlaylistItem: { item in viewModel.removeFromPlaylist(messageId: message.id, item: item) },
                            isStreaming: isStreaming
                        )
                        .id(message.id)

                        if let receipts = viewModel.actionReceipts[message.id], !receipts.isEmpty {
                            AtlasActionReceiptsView(receipts: receipts)
                        }
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
            #if !os(tvOS)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onChanged { _ in dismissKeyboard() }
            )
            #endif
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
    var playlistItems: [MediaItem]?
    var isSavedToList: Bool = false
    var filterPanel: AIService.AIFilterPanel?
    var onCreateList: ((AIService.AIFilterPanel) -> Void)?
    var onRemovePlaylistItem: ((MediaItem) -> Void)?
    var isStreaming: Bool
    
    @State private var selectedMediaItem: MediaItem?
    
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
            playlistItems: playlistItems,
            isSavedToList: isSavedToList,
            filterPanel: filterPanel,
            onCreateList: onCreateList,
            onRemovePlaylistItem: onRemovePlaylistItem,
            isStreaming: isStreaming
        )
        .mediaDetailPresentation(item: $selectedMediaItem)
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

// MARK: - Welcome View (immersive Atlas design)
private struct WelcomeView: View {
    let onSuggestion: (String) -> Void
    @State private var showPrivacyBanner = true
    @State private var glowPulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 64)

            // Atlas icon with animated ambient glow
            ZStack {
                // Outer ambient glow (animates)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.40, green: 0.30, blue: 0.95).opacity(glowPulse ? 0.55 : 0.30),
                                Color.clear
                            ],
                            center: .center, startRadius: 10, endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: glowPulse)

                // Glass circle
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        Circle().stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(red: 0.72, green: 0.60, blue: 1.0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear { glowPulse = true }

            Spacer().frame(height: 28)

            VStack(spacing: 6) {
                Text("Ask Atlas")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Your AI movie & TV assistant")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.50))
            }

            Spacer().frame(height: 40)

            VStack(spacing: 10) {
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

            Spacer().frame(height: 20)

            if showPrivacyBanner {
                AtlasPrivacyBanner(isVisible: $showPrivacyBanner)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()
        }
    }
}

// MARK: - Atlas Privacy Banner
struct AtlasPrivacyBanner: View {
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.caption)
                .foregroundStyle(Color.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Content Safety")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.80))

                Text("All responses are filtered for 13+ appropriateness")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    isVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.40))
                    .padding(6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - AI Input Bar
// MARK: - Attached Images Preview
/// Horizontal row of thumbnails staged for the next message, each removable.
private struct AttachedImagesPreview: View {
    @Binding var images: [Data]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                    ZStack(alignment: .topTrailing) {
                        if let image = imageFromData(data) {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                                )
                        }

                        Button {
                            guard images.indices.contains(index) else { return }
                            images.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, .black.opacity(0.55))
                                .background(Circle().fill(Color.black.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
        .padding(.bottom, 4)
    }

    private func imageFromData(_ data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}

struct AIInputBar: View {
    @Binding var inputText: String
    let isLoading: Bool
    @Binding var isAgentModeEnabled: Bool
    @Binding var attachedImages: [Data]
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ModelRoutingRow(isAgentModeEnabled: $isAgentModeEnabled)

            if !attachedImages.isEmpty {
                AttachedImagesPreview(images: $attachedImages)
            }

            AIInputTextField(
                inputText: $inputText,
                isLoading: isLoading,
                isAgentModeEnabled: $isAgentModeEnabled,
                attachedImages: $attachedImages,
                isInputFocused: isInputFocused,
                onSend: onSend
            )
        }
        .background(
            Color.white.opacity(0.05)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
    }
}

// MARK: - Model Routing
private struct ModelRoutingRow: View, Equatable {
    @Binding var isAgentModeEnabled: Bool

    static func == (lhs: ModelRoutingRow, rhs: ModelRoutingRow) -> Bool {
        lhs.isAgentModeEnabled == rhs.isAgentModeEnabled
    }

    var body: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAgentModeEnabled.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isAgentModeEnabled ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                        .font(.caption)
                    Text("Agent")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(isAgentModeEnabled ? .white : .white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isAgentModeEnabled
                                ? LinearGradient(colors: [Color(red: 0.30, green: 0.50, blue: 0.98), Color(red: 0.34, green: 0.24, blue: 0.82)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.10)], startPoint: .leading, endPoint: .trailing)
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

// MARK: - Input Text Field
private struct AIInputTextField: View {
    @Binding var inputText: String
    let isLoading: Bool
    @Binding var isAgentModeEnabled: Bool
    @Binding var attachedImages: [Data]
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    #if !os(tvOS)
    @State private var photoItems: [PhotosPickerItem] = []
    #endif
    #if os(iOS)
    @State private var showVoiceMode = false
    #endif

    private var trimmedEmpty: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var remainingImageSlots: Int {
        max(0, AIInputState.maxAttachedImages - attachedImages.count)
    }

    var body: some View {
        #if os(iOS)
        if let session = AtlasInlineVoice.shared.session {
            voiceRow(session: session)
        } else {
            composerRow
        }
        #else
        composerRow
        #endif
    }

    #if os(iOS)
    /// The call, in the composer's own slot: the wave takes the text field and
    /// mute + hang up take the attach and send buttons, so voice happens inside
    /// the chat rather than on a screen stacked over it.
    private func voiceRow(session: AtlasVoiceSession) -> some View {
        HStack(alignment: .center, spacing: 10) {
            AtlasVoiceLiveWave(session: session, size: .inline)

            AtlasVoiceCallButton(
                symbol: session.isMuted ? "mic.slash.fill" : "mic.fill",
                tint: session.isMuted ? .orange : .white,
                glassTint: nil,
                diameter: 34,
                accessibilityText: session.isMuted ? "Unmute" : "Mute"
            ) {
                AtlasInlineVoice.shared.toggleMute()
            }

            AtlasVoiceCallButton(
                symbol: "phone.down.fill",
                tint: .white,
                glassTint: .red,
                diameter: 34,
                accessibilityText: "End call"
            ) {
                AtlasInlineVoice.shared.end()
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .onChange(of: session.phase) { _, phase in
            guard case .ended(let reason) = phase else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                AtlasInlineVoice.shared.handleSessionEnded(reason)
            }
        }
    }
    #endif

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            #if !os(tvOS)
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: max(1, remainingImageSlots),
                matching: .images,
                photoLibrary: .shared()
            ) {
                Image(systemName: attachedImages.isEmpty ? "photo.on.rectangle" : "photo.fill.on.rectangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(remainingImageSlots == 0 ? 0.3 : 0.7))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .disabled(isLoading || remainingImageSlots == 0)
            .padding(.bottom, 3)
            .onChange(of: photoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                let items = newItems
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           attachedImages.count < AIInputState.maxAttachedImages,
                           let normalized = AIInputState.normalizedJPEG(from: data) {
                            attachedImages.append(normalized)
                        }
                    }
                    photoItems = []
                }
            }
            #endif

            #if os(tvOS)
            TextField("Ask Atlas anything...", text: $inputText, axis: .vertical)
                .focused(isInputFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.10))
                .cornerRadius(18)
                .submitLabel(.send)
                .onSubmit {
                    guard !trimmedEmpty && !isLoading else { return }
                    onSend()
                }
            #else
            TextEditor(text: $inputText)
                .focused(isInputFocused)
                .frame(minHeight: 36, maxHeight: 100)
                .fixedSize(horizontal: false, vertical: true)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.10))
                .cornerRadius(18)
                .overlay {
                    if inputText.isEmpty {
                        HStack {
                            Text("Ask Atlas anything...")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(.leading, 12)
                                .allowsHitTesting(false)
                            Spacer()
                        }
                    }
                }
            #endif

            #if os(iOS)
            // Tap talks to Atlas right here in the bar; press-and-hold takes
            // the call full screen, where the timer and tuning live.
            Button {
                isInputFocused.wrappedValue = false
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    AtlasInlineVoice.shared.start()
                }
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                showVoiceMode = true
            })
            .disabled(isLoading)
            .padding(.bottom, 3)
            #endif

            Button {
                onSend()
            } label: {
                ZStack {
                    if trimmedEmpty {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 34, height: 34)
                    } else {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.30, green: 0.50, blue: 0.98), Color(red: 0.34, green: 0.24, blue: 0.82)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 34, height: 34)
                    }
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(trimmedEmpty ? Color.white.opacity(0.30) : Color.white)
                }
            }
            .disabled(trimmedEmpty || isLoading)
            .padding(.bottom, 3)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        #if os(iOS)
        .fullScreenCover(isPresented: $showVoiceMode) {
            AtlasVoiceView()
        }
        .onChange(of: showVoiceMode) { _, presented in
            // One call at a time: going full screen hands the session over.
            if presented { AtlasInlineVoice.shared.end() }
        }
        #endif
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
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.09))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                )
        }
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
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
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
            PlatformURLHandler.openURL(link.url)
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
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .foregroundStyle(.blue.opacity(0.90))
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
    var playlistItems: [MediaItem]?
    var isSavedToList: Bool = false
    var filterPanel: AIService.AIFilterPanel?
    var onCreateList: ((AIService.AIFilterPanel) -> Void)?
    var onRemovePlaylistItem: ((MediaItem) -> Void)?
    var isStreaming: Bool = false
    
    @State private var showTrailerPlayer = false
    @State private var showThinking = false

    private var isUser: Bool { message.role == "user" }

    /// The user's attached images decoded from the message's base64 list.
    private var attachedImages: [Image] {
        #if canImport(UIKit)
        guard let list = message.imageBase64s else { return [] }
        return list.compactMap { b64 in
            guard let data = Data(base64Encoded: b64),
                  let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
        }
        #else
        return []
        #endif
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 56) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom)
                            )
                        Text("Atlas")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.45))
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
                        .foregroundStyle(Color(red: 0.7, green: 0.5, blue: 1.0).opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.14))
                        .cornerRadius(8)
                    }

                    if showThinking {
                        Text(thinking)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(12)
                            .padding(10)
                            .background(Color.purple.opacity(0.08))
                            .cornerRadius(10)
                            .transition(.opacity)
                    }
                }

                if isUser {
                    let images = attachedImages
                    if !images.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: images.count == 1 ? 200 : 104,
                                           height: images.count == 1 ? 200 : 104)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        if isUser {
                            Text(message.content)
                                .font(.body)
                                .foregroundStyle(.white)
                        } else {
                            Text(parsedMarkdown)
                                .foregroundStyle(.white.opacity(0.95))
                        }

                        if isStreaming {
                            BlinkingCursor()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    if isUser {
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.46, blue: 0.97),
                                Color(red: 0.30, green: 0.22, blue: 0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color.white.opacity(0.09)
                    }
                }
                .overlay {
                    if !isUser {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.13), lineWidth: 0.5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                // Source links below the bubble
                if !isUser && !links.isEmpty && !isStreaming {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SOURCES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
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
                                .foregroundStyle(
                                    LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom)
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Watch Trailer")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.90))
                                Text(title)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.50))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                        )
                    }
                    .frame(maxWidth: 260)
                    .sheet(isPresented: $showTrailerPlayer) {
                        TrailerPlayerSheet(videoKey: key, title: title)
                    }
                }
                
                if let panel = filterPanel, !isUser && !isStreaming {
                    AIFilterPanelView(panel: panel) { submittedPanel in
                        onCreateList?(submittedPanel)
                    }
                    .padding(.top, 8)
                }

                if let playlist = playlistItems, !playlist.isEmpty, !isUser && !isStreaming {
                    if AIMessageQuota.isPlusOrAbove() {
                        AIPlaylistView(items: playlist, selectedItem: .constant(nil), isSavedToList: isSavedToList, onRemove: onRemovePlaylistItem)
                            .padding(.top, 8)
                    } else {
                        WGPlusLockedFeatureCard(
                            featureName: "Atlas's Curated Playlist",
                            iconName: "sparkles.rectangle.stack"
                        )
                        .padding(.top, 8)
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
    private let _resolve: @Sendable (inout EnvironmentValues) -> Color
    
    init(_ color: Color) {
        _resolve = { _ in color }
    }
    
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        var env = environment
        return _resolve(&env)
    }
}

// MARK: - Trailer Player Sheet (uses embedded player with autoplay muted)
struct TrailerPlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    Spacer()
                    EmbeddedTrailerPlayer(
                        videoKey: videoKey,
                        title: title
                    )
                    .padding(.horizontal)
                    Spacer()
                }
            }
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.white.opacity(0.25))
                    }
                }
            }
            #if !os(macOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
        }
    }
}

// MARK: - Lightweight Input State
@MainActor
class AIInputState: ObservableObject {
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var isAgentModeEnabled = false
    /// JPEG data for images the user attached to the next message.
    @Published var attachedImages: [Data] = []
    /// Max images allowed per message.
    static let maxAttachedImages = 4

    /// Appends a normalized image, respecting the per-message cap.
    func addImage(_ data: Data) {
        guard attachedImages.count < Self.maxAttachedImages,
              let normalized = Self.normalizedJPEG(from: data) else { return }
        attachedImages.append(normalized)
    }

    /// Downscales picked image data to a sane size and re-encodes as JPEG to keep
    /// the multimodal payload small. Returns nil if the data isn't a valid image.
    nonisolated static func normalizedJPEG(from data: Data, maxDimension: CGFloat = 1024) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
        #else
        return data
        #endif
    }
}

// MARK: - View Model
@MainActor
class AIAssistantViewModel: ObservableObject {
    /// One conversation across every Atlas surface — the dock bar, the sheet,
    /// and anywhere else Atlas is opened from.
    static let shared = AIAssistantViewModel()

    @Published var messages: [AIService.ChatMessage] = []
    @Published var messageCount: Int = 0 // Lightweight counter for conditional checks
    @Published var isThinking = false
    @Published var currentThinkingText = ""
    @Published var streamingMessageId: String? = nil
    @Published var webSearchEnabled = true
    @Published var trailerMessages: [String: (trailerKey: String, trailerTitle: String)] = [:]
    @Published var playlistMessages: [String: [MediaItem]] = [:]
    @Published var playlistSavedToList: [String: Bool] = [:]
    @Published var filterPanelMessages: [String: AIService.AIFilterPanel] = [:]
    /// What Atlas actually did for a message, shown under the bubble. Populated
    /// from executed [ACTION:] tags — never from the model's own claims.
    @Published var actionReceipts: [String: [AtlasActionReceipt]] = [:]
    var pendingListTitle: String? = nil
    @Published var scrollTrigger = 0
    @Published var currentUserQuery = ""
    @Published var remainingMessages = AIMessageQuota.remainingMessages()
    @Published var hasScoutUnlimited = AIMessageQuota.isUnlimited()
    @Published var hasPlusOrAbove = AIMessageQuota.isPlusOrAbove()
    @Published var showUpgradePaywall = false
    
    let inputState = AIInputState()
    
    // Aggressive throttle: buffer content and only push to UI periodically
    private var lastPublishTime: CFAbsoluteTime = 0
    private static let publishInterval: CFAbsoluteTime = 0.12 // ~8fps for content updates
    private static let charThreshold = 40 // minimum chars between UI pushes
    private var lastPublishedLength = 0
    private var pendingFlushTask: Task<Void, Never>?
    private var subscriptionStatusObserver: NSObjectProtocol?
    
    /// Whether Scout should operate in extra-strict kids mode.
    /// Content safety is ALWAYS enforced (via system prompt + output filter).
    /// This flag enables the additional kids-only restrictions on top of baseline safety.
    private var isKidsMode: Bool {
        ScoutAgeGateManager.shared.isKidsRestricted
    }
    
    init() {
        subscriptionStatusObserver = NotificationCenter.default.addObserver(
            forName: ScoutSubscriptionService.statusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshQuotaStatus()
            }
        }
        refreshQuotaStatus()
    }
    
    deinit {
        if let observer = subscriptionStatusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func sendMessage() async {
        let userMessage = inputState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Text is always required — including when an image is attached.
        guard !userMessage.isEmpty else { return }

        // Capture any attached images up-front; images route to the vision path
        // and bypass agent navigation and the trailer short-circuit.
        let attachedImages = inputState.attachedImages
        let hasImages = !attachedImages.isEmpty
        let imageBase64s = attachedImages.map { $0.base64EncodedString() }
        let imageDataURLs = imageBase64s.map { "data:image/jpeg;base64,\($0)" }

        if !hasImages, inputState.isAgentModeEnabled {
            if await handleAgentCommandIfNeeded(userMessage) {
                return
            }
            if ScoutAgentService.shared.looksLikeNavigationOnlyCommand(userMessage) {
                let userChatMessage = AIService.ChatMessage(role: "user", content: userMessage)
                messages.append(userChatMessage)
                messageCount = messages.count
                inputState.inputText = ""
                scrollTrigger += 1

                let assistantMessage = AIService.ChatMessage(
                    role: "assistant",
                    content: "I couldn't find a matching title or person to open."
                )
                messages.append(assistantMessage)
                messageCount = messages.count
                scrollTrigger += 1
                return
            }
        }
        
        // ALWAYS block messages with explicit content — required for App Store 13+ rating
        if !(inputState.isAgentModeEnabled && ScoutAgentService.shared.looksLikeNavigationOnlyCommand(userMessage))
            && ContentFilterService.shared.containsBlockedContent(userMessage) {
            let blockedMsg = AIService.ChatMessage(role: "user", content: userMessage)
            messages.append(blockedMsg)
            messageCount = messages.count
            inputState.inputText = ""
            scrollTrigger += 1
            
            let refusalMsg = AIService.ChatMessage(
                role: "assistant",
                content: ContentFilterService.refusalMessage
            )
            messages.append(refusalMsg)
            messageCount = messages.count
            scrollTrigger += 1
            return
        }

        refreshQuotaStatus()
        if remainingMessages <= 0 {
            showUpgradePaywall = true
            return
        }
        
        AIMessageQuota.consumeMessage()
        refreshQuotaStatus()
        
        let userChatMessage = AIService.ChatMessage(role: "user", content: userMessage, imageBase64s: hasImages ? imageBase64s : nil)
        messages.append(userChatMessage)
        messageCount = messages.count
        inputState.inputText = ""
        inputState.attachedImages = []
        scrollTrigger += 1

        inputState.isLoading = true
        isThinking = true
        currentThinkingText = ""
        currentUserQuery = userMessage

        let kidsMode = isKidsMode

        // Check for trailer short-circuit first (non-streaming). Skipped when
        // images are attached — those always take the vision streaming path.
        let lowercased = userMessage.lowercased()
        let trailerKeywords = ["trailer", "teaser", "preview"]
        let isTrailerRequest = !hasImages && trailerKeywords.contains { lowercased.contains($0) }

        if isTrailerRequest {
            do {
                let likedItems = StorageService.shared.liked
                let (response, trailerResponse) = try await AIService.shared.sendMessage(
                    userMessage,
                    conversationHistory: messages,
                    likedItems: likedItems,
                    webSearchEnabled: webSearchEnabled,
                    restrictedMode: kidsMode
                )
                
                isThinking = false
                
                // Atlas's own layers first: memories to keep, actions to run.
                let (contentNoMemory, learnedMemories) = AtlasMemoryStore.extractMemoryTags(from: response)
                let (contentNoActions, requestedActions) = AtlasActionCenter.extractActionTags(from: contentNoMemory)
                for memory in learnedMemories {
                    AtlasMemoryStore.shared.remember(memory.text, kind: memory.kind)
                }

                // Check for [TRAILER:] tags in the response
                let (rawCleanedContent, trailerTitles) = AIService.extractTrailerTags(from: contentNoActions)
                // ALWAYS filter output — required for App Store 13+ rating
                let cleanedContent = ContentFilterService.shared.filterOutput(
                    AIService.strippingControlTags(rawCleanedContent)
                )
                let assistantMessage = AIService.ChatMessage(role: "assistant", content: cleanedContent)
                messages.append(assistantMessage)
                messageCount = messages.count
                
                if !requestedActions.isEmpty {
                    let receipts = await AtlasActionCenter.shared.execute(requestedActions)
                    if !receipts.isEmpty {
                        actionReceipts[assistantMessage.id] = receipts
                    }
                }

                if let trailer = trailerResponse {
                    trailerMessages[assistantMessage.id] = (trailer.trailerKey, trailer.trailerTitle)
                } else {
                    let (contentNoTrailers, trailerTitles) = AIService.extractTrailerTags(from: contentNoActions)
                    let (contentNoFilter, filterPanel) = AIService.extractFilterPanelTag(from: contentNoTrailers)
                    // Only the side effects are needed here — the visible text was
                    // already cleaned by `strippingControlTags` when the message
                    // was appended above.
                    let (_, playlistTitles) = AIService.extractPlaylistTags(from: contentNoFilter)

                    if let firstTitle = trailerTitles.first {
                        if let result = await AIService.shared.fetchTrailer(for: firstTitle) {
                            trailerMessages[assistantMessage.id] = (result.key, result.title)
                        }
                    }

                    if let panel = filterPanel {
                        filterPanelMessages[assistantMessage.id] = panel
                    }

                    if !playlistTitles.isEmpty {
                        let resolved = await resolvePlaylistTitles(playlistTitles)
                        playlistMessages[assistantMessage.id] = resolved
                        autoSavePlaylistAsCustomList(items: resolved, userQuery: userMessage, messageId: assistantMessage.id)
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
            restrictedMode: kidsMode,
            imageDataURLs: imageDataURLs
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
                // Buffer raw content; content filter is applied once at .done after tag extraction
                pendingContent = text
                
                // Time + char based throttle — only push when enough time AND content has elapsed
                let now = CFAbsoluteTimeGetCurrent()
                let charDelta = text.count - lastPublishedLength
                let timeDelta = now - lastPublishTime
                
                if (charDelta >= Self.charThreshold && timeDelta >= Self.publishInterval) || text.count < 20 {
                    pendingFlushTask?.cancel()
                    // Display-only strip: the real extraction happens at .done,
                    // but a half-written tag must never reach the bubble.
                    messages[streamIndex].content = AIService.strippingControlTags(text)
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
                            self.messages[streamIndex].content = AIService.strippingControlTags(capturedText)
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
                
                // Extract tags BEFORE content filtering so internal app tags ([FILTER_PANEL:], [PLAYLIST:]) are not stripped
                let (contentNoMemory, learnedMemories) = AtlasMemoryStore.extractMemoryTags(from: messages[streamIndex].content)
                let (contentNoActions, requestedActions) = AtlasActionCenter.extractActionTags(from: contentNoMemory)
                for memory in learnedMemories {
                    AtlasMemoryStore.shared.remember(memory.text, kind: memory.kind)
                }
                let (contentNoTrailers, trailerTitles) = AIService.extractTrailerTags(from: contentNoActions)
                let (contentNoFilter, filterPanel) = AIService.extractFilterPanelTag(from: contentNoTrailers)
                let (tagCleanedContent, playlistTitles) = AIService.extractPlaylistTags(from: contentNoFilter)

                // Final pass: ALWAYS filter content — required for App Store 13+ rating.
                // `strippingControlTags` runs after the typed extractors so anything
                // they didn't recognise (malformed or invented tags) is removed too.
                let displayContent = AIService.strippingControlTags(tagCleanedContent)
                messages[streamIndex].content = ContentFilterService.shared.filterOutput(displayContent)
                let msgId = messages[streamIndex].id

                if !requestedActions.isEmpty {
                    let receipts = await AtlasActionCenter.shared.execute(requestedActions)
                    if !receipts.isEmpty {
                        actionReceipts[msgId] = receipts
                    }
                }

                if let firstTitle = trailerTitles.first {
                    if let result = await AIService.shared.fetchTrailer(for: firstTitle) {
                        trailerMessages[msgId] = (result.key, result.title)
                    }
                }

                if let panel = filterPanel {
                    filterPanelMessages[msgId] = panel
                }

                if !playlistTitles.isEmpty {
                    let resolved = await resolvePlaylistTitles(playlistTitles)
                    playlistMessages[msgId] = resolved
                    autoSavePlaylistAsCustomList(items: resolved, userQuery: userMessage, messageId: msgId)
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

    func removeFromPlaylist(messageId: String, item: MediaItem) {
        playlistMessages[messageId]?.removeAll { $0.id == item.id }
        // Also remove from any saved custom list that contains this item
        let savedItem = SavedMediaItem(from: item)
        let matchingList = StorageService.shared.customLists.first { list in
            list.items.contains { $0.id == savedItem.id }
        }
        if let list = matchingList {
            StorageService.shared.removeFromCustomList(listId: list.id, item: savedItem)
        }
    }

    func createListFromPanel(_ panel: AIService.AIFilterPanel) {
        if !panel.title.isEmpty { pendingListTitle = panel.title }

        var criteria: [String] = []
        if !panel.company.isEmpty   { criteria.append("studio: \(panel.company)") }
        if !panel.genre.isEmpty     { criteria.append("genre: \(panel.genre)") }
        if !panel.yearFrom.isEmpty  { criteria.append("released from \(panel.yearFrom) onwards") }
        if !panel.streaming.isEmpty { criteria.append("available on \(panel.streaming)") }

        let titlePart = panel.title.isEmpty ? "a playlist" : "'\(panel.title)'"
        let criteriaText = criteria.isEmpty ? "" : " (\(criteria.joined(separator: ", ")))"
        inputState.inputText = "Create a full playlist titled \(titlePart)\(criteriaText). Include ALL matching titles with no limit."
        Task { await sendMessage() }
    }

    /// Resolves a list of titles to MediaItems concurrently via TMDB, preserving order.
    private func resolvePlaylistTitles(_ titles: [String]) async -> [MediaItem] {
        guard !titles.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, title) in titles.enumerated() {
                group.addTask {
                    let result = try? await TMDBService.shared.searchMulti(query: title)
                    return (index, result?.results.first)
                }
            }
            var pairs: [(Int, MediaItem)] = []
            for await (index, item) in group {
                if let item { pairs.append((index, item)) }
            }
            return pairs.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func autoSavePlaylistAsCustomList(items: [MediaItem], userQuery: String, messageId: String) {
        let storage = StorageService.shared
        let listName: String
        if let pending = pendingListTitle, !pending.isEmpty {
            listName = pending
            pendingListTitle = nil
        } else {
            let raw = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            listName = "Scout: " + (raw.count > 40 ? String(raw.prefix(40)) + "…" : raw)
        }
        guard let newList = storage.createCustomListAndReturn(name: listName, description: "AI-generated playlist", iconName: "sparkles.rectangle.stack") else { return }
        for item in items {
            storage.addToCustomList(listId: newList.id, item: SavedMediaItem(from: item))
        }
        playlistSavedToList[messageId] = true
    }

    private func handleAgentCommandIfNeeded(_ userMessage: String) async -> Bool {
        guard let decision = await ScoutAgentService.shared.decision(for: userMessage, conversationHistory: messages) else {
            return false
        }
        guard decision.action != .none, let title = decision.title else {
            return false
        }

        let userChatMessage = AIService.ChatMessage(role: "user", content: userMessage)
        messages.append(userChatMessage)
        messageCount = messages.count
        inputState.inputText = ""
        scrollTrigger += 1

        let assistantText: String
        switch decision.action {
        case .addToWatchlist:
            let preferredType = preferredMediaType(for: decision.targetType)
            guard let mediaItem = await ScoutAgentService.shared.resolveMediaItem(for: title, preferredType: preferredType) else {
                messages.removeLast()
                messageCount = messages.count
                return false
            }
            let alreadySaved = StorageService.shared.isInWantToWatch(mediaItem.id, mediaType: mediaItem.resolvedMediaType)
            if !alreadySaved {
                StorageService.shared.addToWantToWatch(SavedMediaItem(from: mediaItem))
            }
            assistantText = alreadySaved
                ? "\(mediaItem.displayTitle) is already in your watchlist."
                : "Added \(mediaItem.displayTitle) to your watchlist."

        case .openDetails:
            let preferredType = preferredMediaType(for: decision.targetType)
            guard let mediaItem = await ScoutAgentService.shared.resolveMediaItem(for: title, preferredType: preferredType) else {
                messages.removeLast()
                messageCount = messages.count
                return false
            }
            ScoutAgentRouteCenter.shared.queue(
                ScoutAgentRoute(
                    query: mediaItem.displayTitle,
                    searchType: preferredType ?? mediaItem.resolvedMediaType,
                    opensMediaDetail: true,
                    opensPersonPage: false,
                    preferredItem: mediaItem,
                    preferredPerson: nil
                )
            )
            assistantText = "Opening \(mediaItem.displayTitle)."

        case .openPersonPage:
            guard let person = await ScoutAgentService.shared.resolvePerson(for: title) else {
                messages.removeLast()
                messageCount = messages.count
                return false
            }
            ScoutAgentRouteCenter.shared.queue(
                ScoutAgentRoute(
                    query: person.name,
                    searchType: .person,
                    opensMediaDetail: false,
                    opensPersonPage: true,
                    preferredItem: nil,
                    preferredPerson: person
                )
            )
            assistantText = "Opening \(person.name)."

        case .none:
            return false
        }

        let assistantMessage = AIService.ChatMessage(role: "assistant", content: assistantText)
        messages.append(assistantMessage)
        messageCount = messages.count
        scrollTrigger += 1
        return true
    }

    private func preferredMediaType(for targetType: ScoutAgentTargetType?) -> MediaType? {
        switch targetType {
        case .movie:
            return .movie
        case .tv:
            return .tv
        default:
            return nil
        }
    }

    private func refreshQuotaStatus() {
        remainingMessages = AIMessageQuota.remainingMessages()
        hasScoutUnlimited = AIMessageQuota.isUnlimited()
        hasPlusOrAbove = AIMessageQuota.isPlusOrAbove()
    }
    
    func clearMessages() {
        pendingFlushTask?.cancel()
        messages = []
        messageCount = 0
        trailerMessages = [:]
        actionReceipts = [:]
        currentThinkingText = ""
        currentUserQuery = ""
        isThinking = false
        streamingMessageId = nil
    }
}

#Preview {
    AIAssistantView()
}
