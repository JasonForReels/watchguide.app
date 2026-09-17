import SwiftUI

private struct MediaDetailPresentationModifier: ViewModifier {
    @Binding var item: MediaItem?

    /// Owned here, and handed to the source cards through the environment and
    /// to the detail screen directly, so both ends of the zoom agree on it.
    @Namespace private var zoomNamespace

    func body(content: Content) -> some View {
        content
            .environment(\.wgZoomNamespace, zoomNamespace)
            .fullScreenCover(item: $item) { item in
                // Read at build time rather than through state: the tap handler
                // records the source synchronously before setting `item`, so the
                // value is already correct here and needs no extra update pass.
                MediaDetailView(item: item)
                    .presentationBackground(.black)
                    .wgZoomDestination(id: WGZoom.activeSourceID, in: zoomNamespace)
            }
            .onChange(of: item) { _, newValue in
                if newValue == nil { WGZoom.didDismiss() }
                HeroCarouselMuteManager.shared.isExternallyMuted = (newValue != nil)
            }
    }
}

extension View {
    func mediaDetailPresentation(item: Binding<MediaItem?>) -> some View {
        modifier(MediaDetailPresentationModifier(item: item))
    }
}
