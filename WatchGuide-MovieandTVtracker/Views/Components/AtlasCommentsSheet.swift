//
//  AtlasCommentsSheet.swift
//  WatchGuide-MovieandTVtracker
//
//  Atlas on Pops, laid out like a video's comment section: your questions are
//  comments, Atlas's answers are threaded replies under them, a row of emoji
//  asks the common questions in one tap, and the composer sits at the bottom
//  with your avatar. Questions are tied to the clip's title, shown the way a
//  comment shows an @mention, so Atlas always knows what "it" is.
//

import SwiftUI

#if !os(tvOS)

struct AtlasCommentsSheet: View {
    let media: MediaItem
    /// Only messages from this moment on belong to this clip's thread; the rest
    /// of the Atlas conversation stays out of it.
    let threadStart: Date

    @ObservedObject private var viewModel = AIAssistantViewModel.shared
    @ObservedObject private var inputState = AIAssistantViewModel.shared.inputState
    @ObservedObject private var profiles = ProfileService.shared
    @AppStorage(AtlasPersona.storageKey) private var personaRaw = AtlasPersona.default.rawValue
    @FocusState private var isInputFocused: Bool
    @State private var likedReplies: Set<String> = []

    private struct QuickAsk: Identifiable {
        let emoji: String
        let label: String
        let question: String
        var id: String { emoji }
    }

    private let quickAsks: [QuickAsk] = [
        QuickAsk(emoji: "🍿", label: "Worth it", question: "Is it worth watching? Give me a quick, spoiler-free verdict."),
        QuickAsk(emoji: "📺", label: "Where", question: "Where can I stream it?"),
        QuickAsk(emoji: "🎭", label: "Cast", question: "Who's in it?"),
        QuickAsk(emoji: "🔁", label: "Similar", question: "What should I watch next if I like it?"),
        QuickAsk(emoji: "🧠", label: "Explain", question: "What's it about? No spoilers."),
        QuickAsk(emoji: "🔥", label: "Hype", question: "Why is everyone talking about it?")
    ]

    private var persona: AtlasPersona {
        AtlasPersona(rawValue: personaRaw) ?? .default
    }

    private var thread: [AIService.ChatMessage] {
        viewModel.messages.filter {
            $0.timestamp >= threadStart && ($0.role == "user" || $0.role == "assistant")
        }
    }

    /// Questions are sent as "About <title> (<year>): …" so the model has the
    /// context; the comment shows that prefix as an @mention instead.
    private var mentionPrefix: String {
        if let year = media.year {
            return "About \(media.displayTitle) (\(year)): "
        }
        return "About \(media.displayTitle): "
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        suggestionRow
                            .padding(.top, 18)
                            .padding(.bottom, 14)

                        if thread.isEmpty && !viewModel.isThinking {
                            emptyState
                        } else {
                            comments
                        }

                        Color.clear.frame(height: 1).id(Self.bottomAnchor)
                    }
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messageCount) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: thread.last?.content) { _, _ in
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }

            Divider().overlay(Color.white.opacity(0.08))
            emojiRow
            composer
        }
        .background(Color(white: 0.11).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.showUpgradePaywall) {
            WGUnlimitedPaywallView()
        }
    }

    // MARK: Header row

    private var suggestionRow: some View {
        Button { ask(quickAsks[0].question) } label: {
            HStack(spacing: 10) {
                AtlasMark(size: 20, tint: .accentBlue)
                Text("Ask · Is \(media.displayTitle) worth watching?")
                    .lineLimit(1)
            }
            .font(.body)
            .foregroundStyle(Color.accentBlue)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isThinking)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No questions yet")
                .font(.title3.weight(.bold))
            Text("Ask Atlas anything about \(media.displayTitle).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: Comments

    private var comments: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(thread) { message in
                if message.role == "user" {
                    commentRow(message, isReply: false)
                } else {
                    commentRow(message, isReply: true)
                }
            }
            if viewModel.isThinking && thread.last?.role != "assistant" {
                thinkingRow
            }
        }
        .padding(.bottom, 16)
    }

    private func commentRow(_ message: AIService.ChatMessage, isReply: Bool) -> some View {
        let isAtlas = message.role == "assistant"
        let text = isAtlas ? AtlasDockBar.stripControlTags(message.content) : message.content
        return HStack(alignment: .top, spacing: 12) {
            avatar(isAtlas: isAtlas, size: isReply ? 34 : 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isAtlas ? "atlas" : displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(age(of: message.timestamp))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isAtlas {
                        Text("· AI")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                commentText(text, isAtlas: isAtlas)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                Button("Reply") { isInputFocused = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isAtlas {
                likeButton(for: message.id)
            }
        }
        .padding(.leading, isReply ? 54 : 0)
    }

    private func commentText(_ text: String, isAtlas: Bool) -> Text {
        if !isAtlas, text.hasPrefix(mentionPrefix) {
            let rest = String(text.dropFirst(mentionPrefix.count))
            return Text("@\(media.displayTitle) ").foregroundColor(.accentBlue) + Text(rest)
        }
        return Text(text.isEmpty ? " " : text)
    }

    private var thinkingRow: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(isAtlas: true, size: 34)
            VStack(alignment: .leading, spacing: 6) {
                Text("atlas")
                    .font(.subheadline.weight(.semibold))
                AtlasMark(size: 20, isThinking: true)
            }
            Spacer()
        }
        .padding(.leading, 54)
        .accessibilityLabel("Atlas is typing")
    }

    private func likeButton(for id: String) -> some View {
        let liked = likedReplies.contains(id)
        return Button {
            if liked { likedReplies.remove(id) } else { likedReplies.insert(id) }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 18))
                .foregroundStyle(liked ? .red : .secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(liked ? "Unlike reply" : "Like reply")
    }

    @ViewBuilder
    private func avatar(isAtlas: Bool, size: CGFloat) -> some View {
        if isAtlas {
            // Atlas wears a story-style ring in its persona colour.
            ZStack {
                Circle()
                    .fill(persona.accentColor.opacity(0.35))
                AtlasMark(size: size * 0.46, tint: .white)
            }
            .frame(width: size, height: size)
            .padding(2.5)
            .overlay(
                Circle().strokeBorder(
                    AngularGradient(colors: [persona.accentColor, .pink, .orange, persona.accentColor],
                                    center: .center),
                    lineWidth: 2
                )
            )
        } else {
            userAvatar(size: size)
        }
    }

    @ViewBuilder
    private func userAvatar(size: CGFloat) -> some View {
        if let profile = profiles.activeProfile {
            ProfileAvatarImageView(profile: profile, size: size, showBorder: false)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    private var displayName: String {
        let name = profiles.activeProfile?.name ?? "you"
        return name.lowercased().filter { !$0.isWhitespace }
    }

    // MARK: Emoji asks + composer

    private var emojiRow: some View {
        HStack(spacing: 0) {
            ForEach(quickAsks) { quick in
                Button { ask(quick.question) } label: {
                    VStack(spacing: 3) {
                        Text(quick.emoji).font(.system(size: 28))
                        Text(quick.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(quick.question)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .disabled(viewModel.isThinking)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            userAvatar(size: 44)

            HStack(spacing: 8) {
                TextField("Ask Atlas about \(media.displayTitle)…", text: $inputState.inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit { ask(inputState.inputText) }

                if !inputState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { ask(inputState.inputText) } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, persona.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isThinking)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .background(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: Sending

    private func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !viewModel.isThinking else { return }
        // A question that already names the title doesn't need the mention.
        let mentionsTitle = trimmed.localizedCaseInsensitiveContains(media.displayTitle)
        inputState.inputText = mentionsTitle ? trimmed : mentionPrefix + trimmed
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        Task { await viewModel.sendMessage() }
    }

    private func age(of date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    private static let bottomAnchor = "atlas-comments-bottom"
}

private extension Color {
    /// The link blue a comment section uses for mentions and suggestions.
    static let accentBlue = Color(red: 0.36, green: 0.62, blue: 1.0)
}

#endif
