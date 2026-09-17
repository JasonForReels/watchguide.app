import SwiftUI

struct HubCollectionView: View {
    let collection: HubCollection
    
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    
    var body: some View {
        ImmersiveHubLayout(
            items: items,
            logo: collectionLogo,
            backgroundColor: collection.backgroundColor
        )
        .overlay(loadingOverlay)
        .task {
            await loadCollection()
        }
    }
    
    @ViewBuilder
    private var collectionLogo: some View {
        Image(collection.logoAssetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 80)
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoading {
            ZStack {
                collection.backgroundColor.ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
    }
    
    private func loadCollection() async {
        isLoading = true
        do {
            let collectionItems: [MediaItem]
            
            if let customItems = collection.customItems {
                // Fetch each item in parallel
                collectionItems = await withTaskGroup(of: MediaItem?.self) { group in
                    for item in customItems {
                        group.addTask {
                            do {
                                if item.type == .tv {
                                    let show = try await TMDBService.shared.getTVShowDetails(id: Int(item.id) ?? 0)
                                    return MediaItem(from: show)
                                } else {
                                    let movie = try await TMDBService.shared.getMovieDetails(id: Int(item.id) ?? 0)
                                    return MediaItem(from: movie)
                                }
                            } catch {
                                print("Error fetching custom item \(item.id): \(error)")
                                return nil
                            }
                        }
                    }
                    
                    var results: [MediaItem] = []
                    for await item in group {
                        if let item = item {
                            results.append(item)
                        }
                    }
                    return results.sorted { 
                        ($0.releaseDate ?? $0.firstAirDate ?? "") > ($1.releaseDate ?? $1.firstAirDate ?? "")
                    }
                }
            } else {
                let details = try await TMDBService.shared.getCollectionDetails(id: collection.id)
                let now = Date()
                
                collectionItems = details.parts.filter { item in
                    let dateStr = item.releaseDate ?? item.firstAirDate ?? ""
                    if let date = TMDBService.shared.date(from: dateStr) {
                        return date <= now
                    }
                    return true
                }.sorted { 
                    ($0.releaseDate ?? $0.firstAirDate ?? "") > ($1.releaseDate ?? $1.firstAirDate ?? "")
                }
            }
            
            await MainActor.run {
                self.items = collectionItems
                self.isLoading = false
            }
        } catch {
            print("Failed to load collection \(collection.name): \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}
