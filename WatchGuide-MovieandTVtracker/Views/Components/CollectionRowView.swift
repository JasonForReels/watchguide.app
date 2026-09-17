//
//  CollectionRowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct CollectionRowView: View {
    let collectionName: String
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(collectionName)
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        FocusableActionSurface(
                            action: { onItemTap(item) },
                            outlineShape: .roundedRectangle(cornerRadius: 18)
                        ) {
                            MediaPosterCard(item: item)
                        }
                    }
                }
                .padding(.horizontal)
                #if os(tvOS)
                .padding(.vertical, 4)
                #endif
            }
            .scrollClipDisabled()
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }
}
