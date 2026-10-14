//
//  SimklSettingsContent.swift
//  WatchGuide-MovieandTVtracker
//
//  Connect / sync controls for Simkl, shown in Settings on iOS and tvOS.
//

import SwiftUI
#if os(tvOS)
import CoreImage.CIFilterBuiltins
#endif

struct SimklSettingsContent: View {
    @ObservedObject private var simkl = SimklService.shared
    @State private var statusMessage: String?

    var body: some View {
        if simkl.isConnected {
            connected
        } else if simkl.isConfigured {
            connectButton
        } else {
            Text("Add `SIMKL_CLIENT_ID` to your app keys to enable Simkl.")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if let statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        // Simkl's API rules ask apps to credit Simkl wherever it is used.
        Link(destination: URL(string: "https://simkl.com")!) {
            Label("Powered by Simkl", systemImage: "arrow.up.right.square")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var connected: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
            if let username = simkl.username {
                Text(username)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        Toggle(isOn: $simkl.checkInEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Check In When I Press Play")
                Text("Shows the title as Watching on Simkl when you open it in a streaming app. Simkl marks it watched once its runtime has passed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        Button {
            run {
                let summary = try await simkl.importLibrary()
                return summary.unchanged
                    ? "Nothing new on Simkl since the last sync."
                    : "Synced from Simkl: \(summary.watchlistCount) want to watch, \(summary.watchedCount) watched, \(summary.likedCount) liked."
            }
        } label: {
            Label("Sync Simkl to WatchGuide", systemImage: "arrow.down.left.arrow.up.right")
        }
        .disabled(simkl.isBusy)

        Button {
            run {
                let summary = try await simkl.exportLibrary()
                return "Sent to Simkl: \(summary.watchlistCount) want to watch, \(summary.watchedCount) watched, \(summary.likedCount) liked."
            }
        } label: {
            Label("Sync WatchGuide to Simkl", systemImage: "arrow.up.right.arrow.down.left")
        }
        .disabled(simkl.isBusy)

        Button("Disconnect", role: .destructive) {
            simkl.disconnect()
            statusMessage = "Disconnected Simkl."
        }
        .disabled(simkl.isBusy)
    }

    @ViewBuilder
    private var connectButton: some View {
        Button {
            run {
                try await simkl.connect()
                return "Connected Simkl. Your list changes now sync automatically."
            }
        } label: {
            HStack {
                if simkl.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(simkl.tvActivation == nil ? "Connect Simkl" : "Waiting for Simkl Approval")
            }
        }
        .disabled(simkl.isBusy)

        #if os(tvOS)
        if let activation = simkl.tvActivation {
            SimklTVActivationView(activation: activation)
        } else {
            Text("Start the connection, then scan the QR code with your phone to approve it on Simkl.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        #endif
    }

    private func run(_ action: @escaping () async throws -> String) {
        Task {
            do {
                statusMessage = try await action()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

#if os(tvOS)
private struct SimklTVActivationView: View {
    let activation: SimklTVActivation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let qrImage = qrCodeImage(for: activation.verificationURL.absoluteString) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Scan with your phone, or go to simkl.com/pin and enter:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(activation.userCode)
                    .font(.headline.monospaced())
                Text("This code expires at \(activation.expiresAt.formatted(date: .omitted, time: .shortened)).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func qrCodeImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif
