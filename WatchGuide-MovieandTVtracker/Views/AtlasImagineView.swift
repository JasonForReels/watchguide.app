import SwiftUI

// MARK: - Flux Model

enum FluxModel: String, CaseIterable, Identifiable {
    case klein4b = "@cf/black-forest-labs/flux-2-klein-4b"
    case klein9b = "@cf/black-forest-labs/flux-2-klein-9b"
    case dev     = "@cf/black-forest-labs/flux-2-dev"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .klein4b: return "Klein 4B"
        case .klein9b: return "Klein 9B"
        case .dev:     return "Flux Dev"
        }
    }

    var badge: String {
        switch self {
        case .klein4b: return "Fast"
        case .klein9b: return "Balanced"
        case .dev:     return "Quality"
        }
    }

    var steps: Int {
        switch self {
        case .klein4b: return 4
        case .klein9b: return 4
        case .dev:     return 28
        }
    }
}

// MARK: - View

struct AtlasImagineView: View {
    /// Called when the user wants to carry a generated image into the chat as an
    /// attachment. The parent stages it and switches to the Chat tab.
    var onSendToChat: (Data) -> Void = { _ in }

    @State private var prompt = ""
    @State private var selectedModel: FluxModel = .klein9b
    @State private var imageData: Data?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var glowPulse = false
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    if imageData == nil && !isGenerating {
                        welcomeHeader
                    }

                    if let data = imageData {
                        generatedImageCard(data: data)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    if isGenerating {
                        ImagineSpinner()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 50)
                            .transition(.opacity)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 16)
                .animation(.easeInOut(duration: 0.35), value: imageData != nil)
                .animation(.easeInOut(duration: 0.25), value: isGenerating)
                .animation(.easeInOut(duration: 0.2), value: errorMessage)
            }
            .scrollDismissesKeyboard(.interactively)

            inputBar
        }
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 28)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.90, green: 0.28, blue: 0.72).opacity(glowPulse ? 0.52 : 0.24),
                                Color.clear
                            ],
                            center: .center, startRadius: 10, endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                    .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: glowPulse)

                Circle()
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        Circle().stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(red: 1.0, green: 0.58, blue: 0.88)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear { glowPulse = true }

            VStack(spacing: 6) {
                Text("Atlas Imagine")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Describe any scene and bring it to life")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.48))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                promptChip("A cinematic poster for a sci-fi thriller")
                promptChip("Neon-lit Tokyo street at midnight, rain")
                promptChip("Epic fantasy landscape at golden hour")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    private func promptChip(_ text: String) -> some View {
        Button {
            prompt = text
            isPromptFocused = true
        } label: {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Generated Image Card

    @ViewBuilder
    private func generatedImageCard(data: Data) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let img = makeImage(from: data) {
                // Deliberately flat. The card beneath is glass; the picture is
                // a picture — no material, no tint, nothing between you and it.
                img
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    // Lifts it off the glass so it reads as resting on top.
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
            }

            HStack(spacing: 12) {
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(2)

                Spacer()

                Button {
                    onSendToChat(data)
                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.60))
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask Atlas about this image")

                #if canImport(UIKit) && !os(tvOS)
                ShareImageButton(imageData: data)
                #endif
            }
        }
        .padding(16)
        .modifier(ImagineCardGlass(corner: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private func makeImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #endif
        return nil
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            // Model picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FluxModel.allCases) { model in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { selectedModel = model }
                        } label: {
                            HStack(spacing: 5) {
                                Text(model.displayName)
                                    .font(.caption.weight(.semibold))
                                Text(model.badge)
                                    .font(.caption2)
                                    .foregroundStyle(selectedModel == model ? .white.opacity(0.65) : .white.opacity(0.30))
                            }
                            .foregroundStyle(selectedModel == model ? .white : .white.opacity(0.42))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedModel == model
                                          ? LinearGradient(colors: [Color(red: 0.85, green: 0.30, blue: 0.75), Color(red: 0.60, green: 0.20, blue: 0.85)], startPoint: .leading, endPoint: .trailing)
                                          : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)

            HStack(spacing: 12) {
                TextField("Describe an image…", text: $prompt, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.body)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isPromptFocused)

                Button {
                    Task { await generate() }
                } label: {
                    let empty = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                            .frame(width: 34, height: 34)
                    } else if empty {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.22))
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(red: 1.0, green: 0.42, blue: 0.82), Color(red: 0.74, green: 0.28, blue: 0.92)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 34, height: 34)
                    }
                }
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
        }
    }

    // MARK: - Generate

    private func generate() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isPromptFocused = false
        isGenerating = true
        errorMessage = nil
        imageData = nil

        do {
            imageData = try await CloudflareImageService.shared.generateImage(prompt: trimmed, model: selectedModel)
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }
}

// MARK: - Spinner

private struct ImagineSpinner: View {
    @State private var spin = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 2)
                    .frame(width: 68, height: 68)

                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.42, blue: 0.82), Color(red: 0.74, green: 0.28, blue: 0.92)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 68, height: 68)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .onAppear { spin = true }

            Text("Generating your image…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.48))
        }
    }
}

// MARK: - Share Button (UIKit / iOS only)

#if canImport(UIKit) && !os(tvOS)
private struct ShareImageButton: View {
    let imageData: Data
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.60))
                .padding(8)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            if let img = UIImage(data: imageData) {
                ActivityView(items: [img])
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Card glass

/// The sheet the picture rests on.
private struct ImagineCardGlass: ViewModifier {
    let corner: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            content.background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}
