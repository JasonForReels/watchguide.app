import SwiftUI

struct AppleIntelligenceGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var guideManager = AppleIntelligenceGuideManager.shared
    @ObservedObject private var storage = StorageService.shared

    private let report = AppleIntelligenceCapabilityService.currentReport()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    quickToggleCard

                    featureCard(
                        title: "Natural Language Search",
                        isEnabled: report.supportsNaturalLanguageSearch,
                        detail: "Tap Siri search in Search, then ask naturally like: 'Action movies with Jason Statham'.",
                        actionTitle: "Try in Search",
                        destination: .search
                    )

                    featureCard(
                        title: "Image Playground",
                        isEnabled: report.supportsImagePlayground,
                        detail: "Generate images in Atlas chat and Avatar Picker with Apple Intelligence.",
                        actionTitle: "Try in Atlas",
                        destination: .scout
                    )

                    featureCard(
                        title: "Onscreen Awareness",
                        isEnabled: report.supportsOnscreenAwareness,
                        detail: "On movie/show pages, ask Siri: 'What is this movie about?' for richer context.",
                        actionTitle: "Open Browse",
                        destination: .browse
                    )

                    featureCard(
                        title: "Visual Intelligence",
                        isEnabled: report.supportsVisualIntelligence,
                        detail: "Use camera or screenshots to identify posters, then open details, trailers, or add to Watchlist.",
                        actionTitle: "Open Browse",
                        destination: .browse
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("How To Use")
                            .font(.headline)

                        Text("1. Enable Apple Intelligence in device settings.")
                        Text("2. In WatchGuide Settings, turn on Natural Language Search.")
                        Text("3. Use Siri prompts directly in supported screens.")
                        Text("4. Reopen this guide anytime from Settings > Apple Intelligence.")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Apple Intelligence (Beta)")
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

    private var quickToggleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Apple Intelligence")
                    .font(.headline)
                betaTag
            }

            Toggle("Enable Natural Language Search", isOn: Binding(
                get: { storage.settings.useAppleIntelligenceSearch },
                set: { newValue in
                    var updated = storage.settings
                    updated.useAppleIntelligenceSearch = newValue
                    storage.updateSettings(updated)
                }
            ))

            Text("Turn this on to use Apple Intelligence-powered search rewriting across Watch Guide.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.12))
        )
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.platformName)
                .font(.headline)
            HStack(spacing: 8) {
                Image(systemName: report.isAppleIntelligenceAvailableNow ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(report.isAppleIntelligenceAvailableNow ? .green : .orange)
                Text(report.availabilitySummary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.12))
        )
    }

    private func featureCard(
        title: String,
        isEnabled: Bool,
        detail: String,
        actionTitle: String,
        destination: AppleIntelligenceGuideDestination
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isEnabled ? .green : .secondary)
                Text(title)
                    .font(.headline)
                betaTag
            }
            Text(detail)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(actionTitle) {
                guideManager.open(destination)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.12))
        )
    }

    private var betaTag: some View {
        Text("BETA")
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.2))
            )
            .foregroundColor(.orange)
    }
}
