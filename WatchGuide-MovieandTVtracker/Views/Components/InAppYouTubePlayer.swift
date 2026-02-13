//
//  InAppYouTubePlayer.swift
//  WatchGuide-MovieandTVtracker
//
//  Uses SFSafariViewController to play YouTube videos in-app.
//  WKWebView iframe embeds are blocked by YouTube's stricter embed
//  verification (error 152/153), so SFSafariViewController is the
//  reliable alternative — it acts as a real browser with proper
//  referer headers and cookie support.
//

import SwiftUI
import SafariServices

// MARK: - Safari-based YouTube Player (UIViewControllerRepresentable)
struct InAppYouTubePlayer: UIViewControllerRepresentable {
    let videoKey: String
    var autoplay: Bool = true

    func makeUIViewController(context: Context) -> SFSafariViewController {
        // Use the standard watch URL — /embed/ URLs fail with error 153 in SFSafariViewController
        let urlString = "https://www.youtube.com/watch?v=\(videoKey)"
        let url = URL(string: urlString) ?? URL(string: "https://www.youtube.com")!
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredBarTintColor = .black
        vc.preferredControlTintColor = .white
        vc.dismissButtonStyle = .done
        // Hide the Safari toolbar for a cleaner look
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // SFSafariViewController doesn't support URL updates after creation;
        // SwiftUI will recreate the view if videoKey changes.
    }
}

// MARK: - Full Screen YouTube Player Sheet
struct YouTubePlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Full-screen Safari player
            YouTubeSafariPlayer(videoKey: videoKey)
                .ignoresSafeArea()

            // Floating close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            }
            .padding(.top, 12)
            .padding(.leading, 16)
        }
        .background(Color.black)
    }
}

// MARK: - Safari VC wrapper that auto-dismisses when user taps Done
struct YouTubeSafariPlayer: UIViewControllerRepresentable {
    let videoKey: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        // Use the standard watch URL — /embed/ URLs fail with error 153 in SFSafariViewController
        let urlString = "https://www.youtube.com/watch?v=\(videoKey)"
        let url = URL(string: urlString) ?? URL(string: "https://www.youtube.com")!
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredBarTintColor = .black
        vc.preferredControlTintColor = .white
        vc.dismissButtonStyle = .done
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            dismiss()
        }
    }
}
