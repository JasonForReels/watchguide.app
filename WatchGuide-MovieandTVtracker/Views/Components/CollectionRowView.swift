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
                        MediaPosterCard(item: item)
                            .onTapGesture {
                                onItemTap(item)
                            }
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }
}
