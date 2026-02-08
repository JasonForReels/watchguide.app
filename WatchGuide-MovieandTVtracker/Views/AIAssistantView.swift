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
                        LazyVStack(spacing: 16) {
                            // Welcome message
                            if viewModel.messages.isEmpty {
                                welcomeView
                            }
                            
                            ForEach(viewModel.messages) { message in
                                MessageBubble(
                                    message: message,
                                    trailerKey: viewModel.trailerMessages[message.id]?.trailerKey,
                                    trailerTitle: viewModel.trailerMessages[message.id]?.trailerTitle
                                )
                                .id(message.id)
                            }
                            
                            if viewModel.isLoading {
                                HStack {
                                    TypingIndicator()
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id ?? "loading", anchor: .bottom)
                        }
                    }
                }
                
                Divider()
                
                // Model/Web Search toggles
                HStack(spacing: 16) {
                    // Model selector
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
                                .font(.caption)
                            Text(viewModel.selectedModel.displayName)
                                .font(.caption)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                    .foregroundColor(.primary)
                    
                    // Web search toggle
                    Button {
                        viewModel.webSearchEnabled.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.webSearchEnabled ? "globe" : "globe.badge.chevron.backward")
                                .font(.caption)
                            Text("Web Search")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(viewModel.webSearchEnabled ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                        .foregroundColor(viewModel.webSearchEnabled ? .accentColor : .secondary)
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // Input area
                HStack(spacing: 12) {
                    TextField("Ask Chron anything...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .lineLimit(1...4)
                        .onSubmit {
                            sendMessage()
                        }
                    
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(viewModel.inputText.isEmpty ? .secondary : .accentColor)
                    }
                    .disabled(viewModel.inputText.isEmpty || viewModel.isLoading)
                }
                .padding()
                .background(Color(.systemGray6))
            }
            .navigationTitle("Chron")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            viewModel.clearMessages()
                        } label: {
                            Label("Clear Chat", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var welcomeView: some View {
        VStack(spacing: 24) {
            // Logo
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 8) {
                Text("Meet Chron")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Your AI assistant for discovering movies and TV shows")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Model info
            VStack(spacing: 4) {
                Text("Powered by \(viewModel.selectedModel.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if viewModel.webSearchEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption2)
                        Text("Web search enabled for up-to-date info")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }
            }
            
            // Quick suggestions
            VStack(spacing: 12) {
                Text("Try asking:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    SuggestionButton(text: "What should I watch tonight?") {
                        viewModel.inputText = "What should I watch tonight?"
                        sendMessage()
                    }
                    
                    SuggestionButton(text: "Recommend something like Breaking Bad") {
                        viewModel.inputText = "Recommend something like Breaking Bad"
                        sendMessage()
                    }
                    
                    SuggestionButton(text: "What are the best sci-fi movies?") {
                        viewModel.inputText = "What are the best sci-fi movies?"
                        sendMessage()
                    }
                    
                    SuggestionButton(text: "Show me the trailer for Dune") {
                        viewModel.inputText = "Show me the trailer for Dune"
                        sendMessage()
                    }
                }
            }
        }
        .padding(.vertical, 40)
    }
    
    private func sendMessage() {
        guard !viewModel.inputText.isEmpty else { return }
        Task {
            await viewModel.sendMessage()
        }
    }
}

// MARK: - Suggestion Button
struct SuggestionButton: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .cornerRadius(20)
        }
        .foregroundColor(.primary)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: AIService.ChatMessage
    var trailerKey: String?
    var trailerTitle: String?
    
    @State private var showTrailerPlayer = false
    
    var isUser: Bool {
        message.role == "user"
    }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if !isUser {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text("Chron")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.accentColor : Color(.systemGray5))
                    .foregroundColor(isUser ? .white : .primary)
                    .cornerRadius(16)
                
                // Trailer button if available
                if let key = trailerKey, let title = trailerTitle, !isUser {
                    Button {
                        showTrailerPlayer = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Watch Trailer")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(title)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: 280)
                    .sheet(isPresented: $showTrailerPlayer) {
                        TrailerPlayerSheet(videoKey: key, title: title)
                    }
                }
            }
            .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
            
            if !isUser { Spacer() }
        }
    }
}

// MARK: - Trailer Player Sheet
struct TrailerPlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var isMuted = true
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                // Always starts muted; user taps button to unmute
                YouTubePlayerView(videoKey: videoKey, autoPlay: true, isMuted: isMuted)
                    .ignoresSafeArea()
                
                // Mute/unmute toggle — user gesture triggers player.unMute()
                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding(16)
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

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var animationOffset = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .offset(y: animationOffset == index ? -5 : 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(.systemGray5))
        .cornerRadius(16)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) {
                animationOffset = (animationOffset + 1) % 3
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
    @Published var selectedModel: AIService.ChronModel = .hermes3
    @Published var webSearchEnabled = true
    @Published var trailerMessages: [String: (trailerKey: String, trailerTitle: String)] = [:]
    
    private let modelKey = "chron_selected_model"
    private let webSearchKey = "chron_web_search_enabled"
    
    init() {
        // Load persisted settings
        if let savedModel = UserDefaults.standard.string(forKey: modelKey),
           let model = AIService.ChronModel(rawValue: savedModel) {
            selectedModel = model
        }
        webSearchEnabled = UserDefaults.standard.object(forKey: webSearchKey) as? Bool ?? true
    }
    
    func sendMessage() async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Add user message
        let userChatMessage = AIService.ChatMessage(role: "user", content: userMessage)
        messages.append(userChatMessage)
        inputText = ""
        
        isLoading = true
        
        // Persist settings
        UserDefaults.standard.set(selectedModel.rawValue, forKey: modelKey)
        UserDefaults.standard.set(webSearchEnabled, forKey: webSearchKey)
        
        do {
            let likedItems = StorageService.shared.liked
            let (response, trailerResponse) = try await AIService.shared.sendMessage(
                userMessage,
                conversationHistory: messages,
                likedItems: likedItems,
                webSearchEnabled: webSearchEnabled,
                model: selectedModel
            )
            
            let assistantMessage = AIService.ChatMessage(role: "assistant", content: response)
            messages.append(assistantMessage)
            
            // Store trailer metadata if present
            if let trailer = trailerResponse {
                trailerMessages[assistantMessage.id] = (trailer.trailerKey, trailer.trailerTitle)
            }
        } catch {
            let errorMessage = AIService.ChatMessage(
                role: "assistant",
                content: "Sorry, I encountered an error: \(error.localizedDescription)"
            )
            messages.append(errorMessage)
        }
        
        isLoading = false
    }
    
    func clearMessages() {
        messages = []
        trailerMessages = [:]
    }
}

#Preview {
    AIAssistantView()
}
