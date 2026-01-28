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
                                MessageBubble(message: message)
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
    
    var isUser: Bool {
        message.role == "user"
    }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
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
            }
            .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
            
            if !isUser { Spacer() }
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
    
    func sendMessage() async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Add user message
        let userChatMessage = AIService.ChatMessage(role: "user", content: userMessage)
        messages.append(userChatMessage)
        inputText = ""
        
        isLoading = true
        
        do {
            let likedItems = StorageService.shared.liked
            let response = try await AIService.shared.sendMessage(
                userMessage,
                conversationHistory: messages,
                likedItems: likedItems
            )
            
            let assistantMessage = AIService.ChatMessage(role: "assistant", content: response)
            messages.append(assistantMessage)
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
    }
}

#Preview {
    AIAssistantView()
}
