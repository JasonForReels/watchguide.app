import SwiftUI
#if os(iOS) && canImport(SafariServices)
import SafariServices

/// A SwiftUI wrapper around SFSafariViewController for an in-app browser experience.
struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = UIColor.tintColor
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#else
/// macOS fallback: provide a simple handoff to the system browser.
struct InAppSafariView: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            Text("Open in Browser")
                .font(.headline)
            Text(url.absoluteString)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Button("Open") {
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
#endif
