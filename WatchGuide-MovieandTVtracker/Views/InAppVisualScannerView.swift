import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

#if os(iOS) && canImport(UIKit)
struct InAppVisualScannerView: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss

    @State private var capturedImage: UIImage?
    @State private var matches: [InAppVisualSearchResult] = []
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var isCameraPresented = false

    private var topMatch: InAppVisualSearchResult? {
        matches.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        previewSection
                        resultSection
                    }
                    .padding(20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Visual Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            if capturedImage == nil {
                isCameraPresented = true
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented, onDismiss: handleCameraDismiss) {
            InAppCameraCaptureView { image in
                capturedImage = image
                isCameraPresented = false
            } onCancel: {
                isCameraPresented = false
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let capturedImage {
            Image(uiImage: capturedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        resetAndRetake()
                    } label: {
                        Label("Retake", systemImage: "camera.rotate")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .padding(14)
                }
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(height: 280)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Point the camera at a poster")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if isAnalyzing {
            analysisStatusCard(
                title: "Matching title…",
                subtitle: "Reading poster text and checking TMDB/MDBList."
            )
        } else if let topMatch {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.yellow)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Possible matches")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Pick the correct title")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Spacer()
                }

                ForEach(Array(matches.prefix(5).enumerated()), id: \.element.id) { index, match in
                    visualMatchCard(match, isTopMatch: index == 0)
                }

                if !topMatch.rawDetectedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected text")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.7))

                        Text(topMatch.rawDetectedText.prefix(6).joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        } else if let errorMessage {
            VStack(spacing: 16) {
                analysisStatusCard(
                    title: "No title found",
                    subtitle: errorMessage
                )

                Button {
                    resetAndRetake()
                } label: {
                    Text("Try Again")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            analysisStatusCard(
                title: "Capture a poster",
                subtitle: "We’ll scan the artwork, read the title text, then match it to TMDB and MDBList."
            )
        }
    }

    private func visualMatchCard(_ match: InAppVisualSearchResult, isTopMatch: Bool) -> some View {
        Button {
            selectedItem = match.item
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                PosterImageView(
                    posterPath: match.item.posterPath,
                    backdropPath: match.item.backdropPath,
                    size: .medium,
                    mediaId: match.item.id,
                    mediaType: match.item.resolvedMediaType
                )
                .frame(width: 82, height: 122)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if isTopMatch {
                            Text("Best Match")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.yellow)
                        } else {
                            Text("Match \(matches.firstIndex(where: { $0.id == match.id }).map { $0 + 1 } ?? 0)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer()
                    }

                    Text(match.item.displayTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    Text([match.item.resolvedMediaType.displayName, match.item.year].compactMap { $0 }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))

                    if let fanArtTitleLogoURL = match.fanArtTitleLogoURL {
                        ResilientAsyncImage(url: fanArtTitleLogoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 34, alignment: .leading)
                            default:
                                EmptyView()
                            }
                        }
                    } else if let fanArtTitleName = match.fanArtTitleName, !fanArtTitleName.isEmpty {
                        Text(fanArtTitleName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    if let overview = match.item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }

                    Text("See title")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .background(Color.white.opacity(isTopMatch ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isTopMatch ? Color.yellow.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func analysisStatusCard(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            if isAnalyzing {
                ProgressView()
                    .tint(.white)
            }
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func handleCameraDismiss() {
        guard let capturedImage else {
            dismiss()
            return
        }
        Task {
            await analyze(capturedImage)
        }
    }

    @MainActor
    private func analyze(_ image: UIImage) async {
        isAnalyzing = true
        matches = []
        errorMessage = nil

        do {
            matches = try await InAppVisualSearchService.shared.analyze(image: image)
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    private func resetAndRetake() {
        capturedImage = nil
        matches = []
        errorMessage = nil
        isAnalyzing = false
        isCameraPresented = true
    }
}

private struct InAppCameraCaptureView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImagePicked: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            } else {
                onCancel()
            }
        }
    }
}
#endif
