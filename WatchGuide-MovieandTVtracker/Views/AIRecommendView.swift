//
//  AIRecommendView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct AIRecommendView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var selectedPromptType: AIPromptType?
    @State private var showProviderSheet = false
    @State private var copiedToClipboard = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    headerSection
                    
                    // Recommendation Buttons
                    VStack(spacing: 16) {
                        Text("Get AI Recommendations")
                            .font(.title3)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(AIPromptType.allCases, id: \.self) { promptType in
                            AIPromptButton(
                                promptType: promptType,
                                action: {
                                    selectPrompt(promptType)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Stats Section
                    statsSection
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, 20)
            }
            .navigationTitle("AI")
            .sheet(isPresented: $showProviderSheet) {
                if let promptType = selectedPromptType {
                    AIProviderSheet(
                        promptType: promptType,
                        promptText: generatePrompt(for: promptType)
                    )
                }
            }
            .overlay {
                if copiedToClipboard {
                    copiedToast
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 8) {
                Text("AI Recommendations")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Get personalized suggestions from your favorite AI assistant")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        VStack(spacing: 12) {
            Text("Your Data")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                StatCard(
                    title: "Liked",
                    count: storage.liked.count,
                    iconName: "heart.fill",
                    color: .red
                )
                
                StatCard(
                    title: "Watchlist",
                    count: storage.wantToWatch.count,
                    iconName: "bookmark.fill",
                    color: .accentColor
                )
                
                StatCard(
                    title: "Watched",
                    count: storage.watched.count,
                    iconName: "checkmark.circle.fill",
                    color: .green
                )
            }
            
            Text("This data will be shared with the AI to personalize your recommendations")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Copied Toast
    private var copiedToast: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill")
                Text("Copied to clipboard!")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.85))
            .cornerRadius(25)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: copiedToClipboard)
    }
    
    // MARK: - Actions
    private func selectPrompt(_ promptType: AIPromptType) {
        selectedPromptType = promptType

        #if os(tvOS)
        showProviderSheet = true
        #else
        // Copy to clipboard first
        let prompt = generatePrompt(for: promptType)
        PlatformClipboard.copy(prompt)

        // Show copied toast
        withAnimation {
            copiedToClipboard = true
        }

        // Hide toast after delay and show provider sheet
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                copiedToClipboard = false
            }
            showProviderSheet = true
        }
        #endif
    }
    
    private func generatePrompt(for promptType: AIPromptType) -> String {
        let likedTitles = storage.liked.prefix(20).map { "\($0.title) (\($0.year ?? ""))" }.joined(separator: ", ")
        let watchlistTitles = storage.wantToWatch.prefix(20).map { "\($0.title) (\($0.year ?? ""))" }.joined(separator: ", ")
        let watchedTitles = storage.watched.prefix(20).map { "\($0.title) (\($0.year ?? ""))" }.joined(separator: ", ")
        
        return """
        \(promptType.promptPrefix)
        
        Liked: \(likedTitles.isEmpty ? "None" : likedTitles)
        
        Watchlist: \(watchlistTitles.isEmpty ? "None" : watchlistTitles)
        
        Watched: \(watchedTitles.isEmpty ? "None" : watchedTitles)
        """
    }
}

// MARK: - AI Prompt Type
enum AIPromptType: String, CaseIterable {
    case recommendMovie = "Recommend a Movie"
    case recommendShow = "Recommend a Show"
    case recommendAnime = "Recommend an Anime"
    case whatToWatch = "What Should I Watch Tonight?"
    case hiddenGems = "Find Hidden Gems"
    case similarTo = "Something Similar to My Favorites"
    
    var iconName: String {
        switch self {
        case .recommendMovie: return "film.fill"
        case .recommendShow: return "tv.fill"
        case .recommendAnime: return "sparkles.tv.fill"
        case .whatToWatch: return "questionmark.circle.fill"
        case .hiddenGems: return "star.circle.fill"
        case .similarTo: return "heart.circle.fill"
        }
    }
    
    var promptPrefix: String {
        switch self {
        case .recommendMovie:
            return "Recommend a movie based on the below info:"
        case .recommendShow:
            return "Recommend a TV show based on the below info:"
        case .recommendAnime:
            return "Recommend an anime based on the below info:"
        case .whatToWatch:
            return "What should I watch tonight? Consider my mood might vary. Based on the below info:"
        case .hiddenGems:
            return "Recommend some hidden gems or underrated titles I might have missed based on the below info:"
        case .similarTo:
            return "Recommend something similar to my liked titles based on the below info:"
        }
    }
    
    var description: String {
        switch self {
        case .recommendMovie: return "Get a personalized movie suggestion"
        case .recommendShow: return "Find your next binge-worthy series"
        case .recommendAnime: return "Discover anime tailored to your taste"
        case .whatToWatch: return "Perfect for when you can't decide"
        case .hiddenGems: return "Underrated titles you might love"
        case .similarTo: return "More of what you already enjoy"
        }
    }
}

// MARK: - AI Prompt Button
struct AIPromptButton: View {
    let promptType: AIPromptType
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: promptType.iconName)
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(promptType.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(promptType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.12))
            .cornerRadius(16)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: isPressed)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let count: Int
    let iconName: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(color)
            
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
    }
}

// MARK: - AI Provider Sheet
struct AIProviderSheet: View {
    let promptType: AIPromptType
    let promptText: String
    @Environment(\.dismiss) private var dismiss
    @State private var showAppChoice: AIProvider?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    #if os(tvOS)
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                    
                    Text("Open AI Assistant")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("Choose an AI assistant to open")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    #else
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    
                    Text("Prompt Copied!")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("Choose an AI assistant to open")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    #endif
                }
                .padding(.top, 20)
                
                // Provider Buttons
                VStack(spacing: 12) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        AIProviderButton(provider: provider) {
                            handleProviderSelection(provider)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Tip
                #if os(iOS)
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("Paste the copied prompt into the AI chat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.12))
                .cornerRadius(12)
                .padding(.horizontal)
                #endif
                
                Spacer()
            }
            .navigationTitle("Open AI Assistant")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Open \(showAppChoice?.name ?? "")",
                isPresented: Binding(
                    get: { showAppChoice != nil },
                    set: { if !$0 { showAppChoice = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let provider = showAppChoice {
                    Button("Open in App") {
                        openInApp(provider)
                    }
                    Button("Open in Browser") {
                        openInBrowser(provider)
                    }
                    Button("Cancel", role: .cancel) {
                        showAppChoice = nil
                    }
                }
            } message: {
                Text("Choose how to open \(showAppChoice?.name ?? "")")
            }
        }
        .presentationDetents([.medium])
    }
    
    private func handleProviderSelection(_ provider: AIProvider) {
        // Check if app is installed
        if let appURL = provider.appURL, PlatformURLHandler.canOpenURL(appURL) {
            // App is installed, show choice
            showAppChoice = provider
        } else {
            // App not installed, open in browser directly
            openInBrowser(provider)
        }
    }
    
    private func openInApp(_ provider: AIProvider) {
        if let appURL = provider.appURL {
            PlatformURLHandler.openURL(appURL)
        }
        dismiss()
    }
    
    private func openInBrowser(_ provider: AIProvider) {
        PlatformURLHandler.openURL(provider.webURL)
        dismiss()
    }
}

// MARK: - AI Provider
enum AIProvider: String, CaseIterable {
    case chatGPT = "ChatGPT"
    case gemini = "Gemini"
    case grok = "Grok"
    
    var name: String { rawValue }
    
    var webURL: URL {
        switch self {
        case .chatGPT: return URL(string: "https://chatgpt.com")!
        case .gemini: return URL(string: "https://gemini.google.com/app")!
        case .grok: return URL(string: "https://grok.com")!
        }
    }
    
    var appURL: URL? {
        switch self {
        case .chatGPT: return URL(string: "chatgpt://")
        case .gemini: return URL(string: "googlegemini://")
        case .grok: return URL(string: "grok://")
        }
    }
    
    var iconName: String {
        switch self {
        case .chatGPT: return "bubble.left.and.bubble.right.fill"
        case .gemini: return "diamond.fill"
        case .grok: return "bolt.fill"
        }
    }
    
    var logoURL: String {
        switch self {
        case .chatGPT: return "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4d/OpenAI_Logo.svg/640px-OpenAI_Logo.svg.png"
        case .gemini: return "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d9/Google_Gemini_logo_2025.svg/640px-Google_Gemini_logo_2025.svg.png"
        case .grok: return "https://upload.wikimedia.org/wikipedia/commons/thumb/6/62/Grok_2025.png/640px-Grok_2025.png"
        }
    }
    
    var color: Color {
        switch self {
        case .chatGPT: return Color(red: 0.4, green: 0.65, blue: 0.6)
        case .gemini: return Color(red: 0.5, green: 0.5, blue: 0.9)
        case .grok: return Color(red: 0.3, green: 0.3, blue: 0.3)
        }
    }
}

// MARK: - AI Provider Button
struct AIProviderButton: View {
    let provider: AIProvider
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Logo from URL with white rendering
                AsyncImage(url: URL(string: provider.logoURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(colorScheme == .light ? .black : .white)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                    case .failure, .empty:
                        ZStack {
                            Circle()
                                .fill(provider.color.opacity(0.2))
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: provider.iconName)
                                .font(.title3)
                                .foregroundColor(provider.color)
                        }
                    @unknown default:
                        ZStack {
                            Circle()
                                .fill(provider.color.opacity(0.2))
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: provider.iconName)
                                .font(.title3)
                                .foregroundColor(provider.color)
                        }
                    }
                }
                .frame(width: 48, height: 48)
                
                Text(provider.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.12))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AIRecommendView()
}
