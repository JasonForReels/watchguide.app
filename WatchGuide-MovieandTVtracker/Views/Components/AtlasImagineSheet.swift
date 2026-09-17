//
//  AtlasImagineSheet.swift
//  WatchGuide-MovieandTVtracker
//
//  Imagine is the one Atlas surface that still gets its own sheet: it makes
//  pictures, not conversation, and a generated image needs more room than the
//  dock bar has to give.
//
//  The chrome is Liquid Glass; the picture is not. A generated image rendered
//  *as* glass would be tinted and translucent — it would stop being the image.
//  So the glass is the surface it rests on, and the image sits on top of it
//  opaque, with a shadow: a photograph laid on a sheet of glass.
//

import SwiftUI

#if !os(tvOS)

struct AtlasImagineSheet: View {
    /// Carries a generated image back into Atlas as an attachment.
    let onSendToChat: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AtlasImagineView(onSendToChat: onSendToChat)
            }
            .navigationTitle("Imagine")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.regularMaterial)
    }
}

#endif
