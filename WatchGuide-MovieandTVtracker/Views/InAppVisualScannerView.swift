import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
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
                    Image(systemName: "viewfinder.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.yellow)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Best Match")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(topMatch.item.displayTitle)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }

                if let year = topMatch.item.year {
                    Text(year)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let overview = topMatch.item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(4)
                }

                if let imdb = topMatch.ratingsSummary?.imdbRating {
                    Text("IMDb \(imdb)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Button {
                    selectedItem = topMatch.item
                    dismiss()
                } label: {
                    Text("See title")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
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
